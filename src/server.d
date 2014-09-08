import vibe.d, std.algorithm, std.datetime, std.exception, std.file, std.path, std.process, std.range;
import core.stdc.errno, core.sys.posix.fcntl, core.sys.posix.unistd, core.sys.posix.signal : SIGINT, SIGKILL;

shared static this()
{
    string bindAddress = "127.0.0.1";
    getOption("bindAddress|bind", &bindAddress, "Bound network address");
    string sslCert, sslKey;
    ushort httpPort = 8080, httpsPort = 443;
    if (readOption("ssl-cert", &sslCert, "Path to SSL certificate."))
        httpPort = 0;
    readOption("ssl-key", &sslKey, "Path to SSL key.");
    enforce(sslCert.empty == sslKey.empty, "Must provide both SSL key and SSL certificate.");
    if (getOption("https-port", &httpsPort, "HTTPS Port (default: 443)"))
        enforce(!sslCert.empty, "Need a SSL certificate for HTTPS.");
    getOption("http-port", &httpPort, "HTTP Port (default: 80)");

    auto router = new URLRouter;
    router
        .get("/", &drepl)
        .get("/ws/dmd", handleWebSockets(&runSession))
        .get("/*", serveStaticFiles("public"))
        ;

    if (sslCert.empty)
    {
        auto settings = new HTTPServerSettings;
        settings.bindAddresses = [bindAddress];
        settings.port = httpPort;

        listenHTTP(settings, router);
    }
    else
    {
        auto https = new HTTPServerSettings;
        https.bindAddresses = [bindAddress];
        https.port = httpsPort;
        https.sslContext = createSSLContext(SSLContextKind.server, SSLVersion.tls1);
        https.sslContext.useCertificateChainFile(sslCert);
        https.sslContext.usePrivateKeyFile(sslKey);

        listenHTTP(https, router);

        if (httpPort != 0)
        {
            auto fwd = new HTTPServerSettings;
            fwd.bindAddresses = https.bindAddresses;
            fwd.port = httpPort;
            listenHTTP(fwd, (req, res) {
                    auto url = req.fullURL();
                    url.schema = "https";
                    url.port = httpsPort;
                    res.redirect(url);
                });
        }
    }
}

void drepl(HTTPServerRequest req, HTTPServerResponse res)
{
    res.render!"drepl.dt"();
}

void sendError(WebSocket sock, string error)
{
    auto resp = Json.emptyObject;
    resp.state = "error";
    resp.stdout = Json.emptyArray;
    resp.stderr = [Json(error)];
    sock.send((scope stream) => writeJsonString(stream, resp));
}

void runSession(scope WebSocket sock)
{
    immutable id = allocSession();
    if (id == size_t.max)
        return sock.sendError("Too many active users, try again later.");
    scope (exit) freeSession(id);

    auto p = sandBox(id);
    fcntl(p.stdout.fileno, F_SETFL, O_NONBLOCK);

    scope readEvt = createFileDescriptorEvent(p.stdout.fileno, FileDescriptorEvent.Trigger.read);

    Appender!(char[]) buf;

    while (sock.waitForData(5.minutes))
    {
        string msg;
        try
            msg = sock.receiveText(true);
        catch (Exception e)
            return sock.sendError("Received invalid WebSocket message.");

        p.stdin.writeln(msg);
        p.stdin.flush();

        if (!readEvt.wait(5.seconds, FileDescriptorEvent.Trigger.read))
            return sock.sendError("Command '"~msg~"' timed out.");

        auto rc = tryWait(p.pid);
        if (rc.terminated)
            return sock.sendError("Command '"~msg~"' terminated with "~to!string(rc.status)~".");

        char[1024] smBuf = void;
        ptrdiff_t res;
        while ((res = read(p.stdout.fileno, &smBuf[0], smBuf.length)) == smBuf.length)
            buf.put(smBuf[]);

        if (res < 0 && errno != EAGAIN)
            return sock.sendError("Internal error reading process output.");
        buf.put(smBuf[0 .. max(res, 0)]);

        try
        {
            auto resp = parseJsonString(buf.data.idup);
            resp.stdout = resp.stdout.get!string.splitter('\n').map!htmlEscapeMin.map!Json.array;
            resp.stderr = resp.stderr.get!string.splitter('\n').map!htmlEscapeMin.map!Json.array;
            sock.send((scope stream) => writeJsonString(stream, resp));
            buf.clear();
        }
        catch (Exception e)
        {
            return sock.sendError("Internal error reading process output.");
        }
    }

    if (sock.connected)
        return sock.sendError("Connection closed due to inactivity (5 minutes).");
}

__gshared size_t[1024 / (8 * size_t.sizeof)] sessions;

private size_t allocSession()
{
    import std.random, core.bitop : bts;

    foreach (id; iota(0, 8 * size_t.sizeof * sessions.length).randomCover())
        if (!bts(sessions.ptr, id)) return id;
    return size_t.max;
}

private void freeSession(size_t id)
{
    import core.bitop : btc;

    btc(sessions.ptr, id) || assert(0);
}

//------------------------------------------------------------------------------
// Sandbox

// should be in core.stdc.stdlib
version (Posix) extern(C) char* mkdtemp(char* template_);

string mkdtemp(string prefix)
{
    import core.stdc.string : strlen;
    auto tmp = buildPath(tempDir(), prefix~"XXXXXX\0").dup;
    auto dir = mkdtemp(tmp.ptr);
    return dir[0 .. strlen(dir)].idup;
}

// should be in core.sys.linux.selinux.selinux
extern(C) void setfscreatecon(const char*);

auto sandBox(size_t id)
in { assert(id >= 0 && id < 1024 ^^ 2); }
body
{
    import core.runtime : Runtime;

    static struct SandBox
    {
        ~this()
        {
            _p.pid.kill(SIGINT);
            sleep(1.seconds);
            if (!tryWait(_p.pid).terminated)
                _p.pid.kill(SIGKILL);
            rmdirRecurse(_homeDir);
            rmdirRecurse(_tmpDir);
        }

        string _tmpDir, _homeDir;
        ProcessPipes _p;
        alias _p this;
    }

    setfscreatecon("unconfined_u:object_r:sandbox_file_t:s0:c%s,c%s"
                   .format(id / 1024, id % 1024).toStringz());
    auto tmpDir = mkdtemp(".sandbox_tmp_");
    auto homeDir = mkdtemp(".sandbox_home_");
    setfscreatecon(null);
    auto sandbox = Runtime.args[0].replace("drepl_server", "drepl_sandbox").absolutePath.buildNormalizedPath();
    auto path = buildNormalizedPath(homeDir, sandbox.chompPrefix(environment["HOME"]~"/"));
    mkdirRecurse(path.dirName);
    copy(sandbox, path);
    path.setAttributes(sandbox.getAttributes);
    auto p = pipeProcess(["seunshare", "-Z", "unconfined_u:unconfined_r:sandbox_t:s0:c%s,c%s"
                          .format(id / 1024, id % 1024),
                          "-t", tmpDir, "-h", homeDir, "--", sandbox]);
    return SandBox(tmpDir, homeDir, p);
}

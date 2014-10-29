$(document).ready(function() {
    var ws_url = location.protocol.replace('http', 'ws')+'//'+location.hostname+
        (location.port ? ':'+location.port: '')+'/ws/dmd';
    var conn = new WebSocket(ws_url);

    var _writeln;
    function writeln(msg, class_) {
        if (_writeln)
            _writeln(msg, class_);
    }

    var controller = $('#console').console({
        promptLabel: 'D> ',
        continuedPromptLabel: ' | ',
        commandHandle: function(line, cb) {
            _writeln = cb;
            console.log(line);
            conn.send(line);
        },
        autofocus: true,
        animateScroll: true,
        promptHistory: true
    });

    $(".jquery-console-typer").prop("disabled", true);

    conn.onopen = function (e) {
        $(".jquery-console-typer").prop("disabled", false);
    };

    conn.onmessage = function (e) {
        var resp = JSON.parse(e.data);
        console.log(resp.state);
        switch (resp.state)
        {
        case 'incomplete':
            if (controller.continuedPrompt) break;
            controller.continuedPrompt = true;
            writeln("");
            break;
        case 'success':
        case 'error':
            controller.continuedPrompt = false;
            for (var i = 0; i < resp.stdout.length; ++i)
                writeln([{msg: "=> "+resp.stdout[i], className: 'jquery-console-message-success'}]);
            for (var i = 0; i < resp.stderr.length; ++i)
                writeln([{msg: "=> "+resp.stderr[i], className: 'jquery-console-message-error'}]);
            if (resp.stdout.length + resp.stderr.length == 0)
                writeln("");
            break;
        }
    };

    conn.onerror = function (e) {
        controller.notice('A WebSocket error occured \''+e.data+'\'.', 'prompt');
        $(".jquery-console-typer").prop("disabled", true);
    };

    conn.onclose = function (ce) {
        controller.notice('Lost the connection to the server.', 'prompt');
        $(".jquery-console-typer").prop("disabled", true);
    };
});

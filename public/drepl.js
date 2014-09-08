$(document).ready(function() {
    var ws_url = location.protocol.replace('http', 'ws')+'//'+location.hostname+
        (location.port ? ':'+location.port: '')+'/ws/dmd';
    var conn = new WebSocket(ws_url);

    var writeln;

    var controller = $('#console').console({
        promptLabel: 'D> ',
        commandHandle: function(line, cb) {
            writeln = cb
            conn.send(line);
            return true;//[{msg: line, className: 'jquery-console-message-value'}];
        },
        autofocus: true,
        animateScroll: true,
        promptHistory: true,
    });

    var disabled = true;
    // controller.disableInput();

    conn.onopen = function (e) {
        // controller.enableInput();
    }

    conn.onmessage = function (e) {
        var resp = JSON.parse(e.data), prompt = 'D> ';
        switch (resp.state)
        {
        case 'incomplete': prompt = ' |'; break;
        case 'success':
        case 'error':
            for (var i = 0; i < resp.stdout.length; ++i)
                writeln("=> "+resp.stdout[i], 'success');
            for (var i = 0; i < resp.stderr.length; ++i)
                writeln("=> "+resp.stderr[i], 'danger');
            break;
        }
        controller.promptLabel = prompt;
    }

    conn.onerror = function (e) {
        writeln('danger', 'A WebSocket error occured \''+e.data+'\'.');
    };

    conn.onclose = function (ce) {
        writeln('warning', 'Lost the connection to the server.');
    };
});

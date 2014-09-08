jQuery(document).ready(function($) {
    var ws_url = location.protocol.replace('http', 'ws')+'//'+location.hostname+
        (location.port ? ':'+location.port: '')+'/ws/dmd';
    var conn = new WebSocket(ws_url);
    var term = $('#terminal').terminal(
        function(command, term) {
            conn.send(command);
            term.pause();
        }, {
        prompt: "D>&nbsp;",
        greetings: "Type an expression, a statement or a declaration",
        onBlur: function() {
            // prevent loosing focus
            return false;
        }
    });
    term.pause();

    conn.onopen = function (e) {
        term.resume();
    }

    conn.onmessage = function (e) {
        var resp = JSON.parse(e.data), prompt = 'D>&nbsp;';
        switch (resp.state)
        {
        case 'incomplete': prompt = '&nbsp;|&nbsp;'; break;
        case 'success':
        case 'error':
            for (var i = 0; i < resp.stdout.length; ++i)
                term.echo("[[;green;]"+resp.stdout[i]+"]");
            for (var i = 0; i < resp.stderr.length; ++i)
                term.error(resp.stderr[i]);
            break;
        }
        term.set_prompt(prompt);
        term.resume();
    };

    var _hasErr = false;

    conn.onerror = function (e) {
        term.error('A WebSocket error occured \''+e.data+'\'.');
        term.pause();
    };

    conn.onclose = function (ce) {
        term.error('Lost the connection to the server.');
        term.pause();
    };

});

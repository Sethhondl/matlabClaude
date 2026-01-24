function app = launch()
%LAUNCH Launch the Derivux assistant
%
%   DERIVUX.LAUNCH() opens the Derivux assistant panel.
%
%   app = DERIVUX.LAUNCH() returns the app instance.
%
%   Example:
%       derivux.launch()
%
%   See also: derivux.DerivuxApp, derivux.configurePython

    % Auto-configure Python 3.10+ for Claude Agent SDK
    derivux.configurePython();

    app = derivux.DerivuxApp.getInstance();
    app.launch();

    if nargout == 0
        clear app
    end
end

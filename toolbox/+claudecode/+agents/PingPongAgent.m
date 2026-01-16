classdef PingPongAgent < claudecode.agents.BaseAgent
    %PINGPONGAGENT Simple agent that responds to "ping" with "pong"
    %
    %   A demonstration agent showing how to create custom handlers
    %   for specific commands.
    %
    %   Example:
    %       agent = claudecode.agents.PingPongAgent();
    %       if agent.canHandle('ping')
    %           response = agent.handle('ping', struct());
    %       end

    methods
        function obj = PingPongAgent()
            %PINGPONGAGENT Constructor

            obj.Name = 'PingPongAgent';
            obj.Description = 'Responds to ping with pong';
            obj.Priority = 10;  % High priority (low number)
        end

        function tf = canHandle(~, message)
            %CANHANDLE Check if message is "ping"

            tf = strcmpi(strtrim(message), 'ping');
        end

        function response = handle(~, message, context) %#ok<INUSD>
            %HANDLE Respond with pong

            response = 'pong';
        end
    end
end

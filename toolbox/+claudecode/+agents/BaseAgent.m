classdef (Abstract) BaseAgent < handle
    %BASEAGENT Abstract base class for custom agents
    %
    %   Subclass this to create custom agents that can handle specific
    %   commands or patterns before they reach Claude.
    %
    %   Example:
    %       classdef MyAgent < claudecode.agents.BaseAgent
    %           methods
    %               function tf = canHandle(obj, message)
    %                   tf = startsWith(lower(message), 'mycommand');
    %               end
    %               function response = handle(obj, message, context)
    %                   response = 'Handled by MyAgent!';
    %               end
    %           end
    %       end

    properties
        Name = 'BaseAgent'      % Agent name for identification
        Description = ''        % Agent description
        Priority = 100          % Lower number = higher priority
    end

    methods (Abstract)
        % CANHANDLE Check if this agent can handle the given message
        %   tf = canHandle(obj, message) returns true if this agent
        %   should handle the message, false otherwise.
        tf = canHandle(obj, message)

        % HANDLE Process the message and return a response
        %   response = handle(obj, message, context) processes the
        %   message and returns a response string.
        response = handle(obj, message, context)
    end

    methods
        function obj = BaseAgent()
            %BASEAGENT Constructor
        end
    end
end

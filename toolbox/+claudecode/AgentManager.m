classdef AgentManager < handle
    %AGENTMANAGER Manages custom agents and dispatches messages
    %
    %   The AgentManager maintains a list of registered agents and
    %   routes incoming messages to the appropriate agent based on
    %   priority and canHandle() results.
    %
    %   Example:
    %       manager = claudecode.AgentManager();
    %       manager.registerAgent(claudecode.agents.PingPongAgent());
    %       [handled, response] = manager.dispatch('ping', struct());

    properties (Access = private)
        Agents = {}     % Cell array of registered agents
    end

    methods
        function obj = AgentManager()
            %AGENTMANAGER Constructor

            obj.loadDefaultAgents();
        end

        function registerAgent(obj, agent)
            %REGISTERAGENT Add an agent to the manager
            %
            %   manager.registerAgent(agent) adds the agent and
            %   re-sorts by priority.

            obj.Agents{end+1} = agent;
            obj.sortAgentsByPriority();
        end

        function removeAgent(obj, agentName)
            %REMOVEAGENT Remove an agent by name

            idx = [];
            for i = 1:length(obj.Agents)
                if strcmp(obj.Agents{i}.Name, agentName)
                    idx = i;
                    break;
                end
            end

            if ~isempty(idx)
                obj.Agents(idx) = [];
            end
        end

        function agents = getAgents(obj)
            %GETAGENTS Get list of registered agents

            agents = obj.Agents;
        end

        function [handled, response, agentName] = dispatch(obj, message, context)
            %DISPATCH Route message to appropriate agent
            %
            %   [handled, response, agentName] = dispatch(message, context)
            %
            %   Returns:
            %       handled: true if an agent handled the message
            %       response: the agent's response (empty if not handled)
            %       agentName: name of the handling agent (empty if not handled)

            handled = false;
            response = '';
            agentName = '';

            for i = 1:length(obj.Agents)
                agent = obj.Agents{i};

                try
                    if agent.canHandle(message)
                        response = agent.handle(message, context);
                        handled = true;
                        agentName = agent.Name;
                        return;
                    end
                catch ME
                    warning('AgentManager:AgentError', ...
                        'Agent %s threw error: %s', agent.Name, ME.message);
                end
            end
        end
    end

    methods (Access = private)
        function loadDefaultAgents(obj)
            %LOADDEFAULTAGENTS Load built-in agents

            obj.Agents = {};

            % Register PingPong agent
            obj.registerAgent(claudecode.agents.PingPongAgent());
        end

        function sortAgentsByPriority(obj)
            %SORTAGENTSBYPRIORITY Sort agents by priority (lower = higher priority)

            if length(obj.Agents) <= 1
                return;
            end

            priorities = zeros(1, length(obj.Agents));
            for i = 1:length(obj.Agents)
                priorities(i) = obj.Agents{i}.Priority;
            end

            [~, idx] = sort(priorities);
            obj.Agents = obj.Agents(idx);
        end
    end
end

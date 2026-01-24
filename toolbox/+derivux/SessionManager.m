classdef SessionManager < handle
    %SESSIONMANAGER Manages multiple chat sessions for the tabbed interface
    %
    %   This class coordinates session state between JavaScript (tabs) and
    %   Python (conversation contexts). Each tab in the UI corresponds to
    %   an independent session with its own conversation history.
    %
    %   Example:
    %       sm = derivux.SessionManager(pythonBridge);
    %       sm.createSession('tab_123');
    %       sm.switchSession('tab_456');

    properties (Access = private)
        Sessions            % containers.Map<tabId, sessionStruct>
        ActiveSessionId     % Currently active session ID (tabId)
        PythonBridge        % Reference to Python MatlabBridge instance
        Logger              % Logging instance
    end

    methods
        function obj = SessionManager(pythonBridge)
            %SESSIONMANAGER Constructor
            %
            %   obj = SessionManager(pythonBridge)
            %
            %   pythonBridge: Python MatlabBridge instance

            obj.PythonBridge = pythonBridge;
            obj.Sessions = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.ActiveSessionId = '';
            obj.Logger = derivux.logging.Logger.getInstance();

            obj.Logger.info('SessionManager', 'initialized');
        end

        function createSession(obj, tabId)
            %CREATESESSION Create a new session for a tab
            %
            %   createSession(obj, tabId)
            %
            %   tabId: Unique identifier for the tab/session

            if isempty(tabId)
                obj.Logger.warn('SessionManager', 'create_session_empty_id');
                return;
            end

            % Create session struct
            sessionStruct = struct(...
                'tabId', tabId, ...
                'createdAt', now, ...
                'lastActiveAt', now, ...
                'messageCount', 0);

            % Store in map
            obj.Sessions(tabId) = sessionStruct;

            % Notify Python to create session context
            if ~isempty(obj.PythonBridge)
                try
                    obj.PythonBridge.create_session_context(tabId);
                catch ME
                    obj.Logger.warn('SessionManager', 'python_create_session_error', struct(...
                        'tabId', tabId, ...
                        'error', ME.message));
                end
            end

            obj.Logger.info('SessionManager', 'session_created', struct(...
                'tabId', tabId, ...
                'totalSessions', obj.Sessions.Count));
        end

        function closeSession(obj, tabId)
            %CLOSESESSION Close and cleanup a session
            %
            %   closeSession(obj, tabId)
            %
            %   tabId: The tab/session ID to close

            if isempty(tabId) || ~obj.Sessions.isKey(tabId)
                return;
            end

            % If closing active session, clear active
            if strcmp(obj.ActiveSessionId, tabId)
                obj.ActiveSessionId = '';
            end

            % Remove from map
            obj.Sessions.remove(tabId);

            % Notify Python to close session context
            if ~isempty(obj.PythonBridge)
                try
                    obj.PythonBridge.close_session_context(tabId);
                catch ME
                    obj.Logger.warn('SessionManager', 'python_close_session_error', struct(...
                        'tabId', tabId, ...
                        'error', ME.message));
                end
            end

            obj.Logger.info('SessionManager', 'session_closed', struct(...
                'tabId', tabId, ...
                'remainingSessions', obj.Sessions.Count));
        end

        function switchSession(obj, tabId)
            %SWITCHSESSION Switch to a different session
            %
            %   switchSession(obj, tabId)
            %
            %   tabId: The tab/session ID to switch to

            if isempty(tabId)
                return;
            end

            % Create session if it doesn't exist (for initial tab)
            if ~obj.Sessions.isKey(tabId)
                obj.createSession(tabId);
            end

            % Update last active time for old session
            if ~isempty(obj.ActiveSessionId) && obj.Sessions.isKey(obj.ActiveSessionId)
                oldSession = obj.Sessions(obj.ActiveSessionId);
                oldSession.lastActiveAt = now;
                obj.Sessions(obj.ActiveSessionId) = oldSession;
            end

            % Switch active session
            oldSessionId = obj.ActiveSessionId;
            obj.ActiveSessionId = tabId;

            % Update new session's last active time
            if obj.Sessions.isKey(tabId)
                session = obj.Sessions(tabId);
                session.lastActiveAt = now;
                obj.Sessions(tabId) = session;
            end

            % Notify Python to switch session context
            if ~isempty(obj.PythonBridge)
                try
                    obj.PythonBridge.switch_session_context(tabId);
                catch ME
                    obj.Logger.warn('SessionManager', 'python_switch_session_error', struct(...
                        'tabId', tabId, ...
                        'error', ME.message));
                end
            end

            obj.Logger.debug('SessionManager', 'session_switched', struct(...
                'fromTabId', oldSessionId, ...
                'toTabId', tabId));
        end

        function session = getActiveSession(obj)
            %GETACTIVESESSION Get the currently active session
            %
            %   session = getActiveSession(obj)
            %
            %   Returns: Session struct or empty struct if no active session

            session = struct();

            if ~isempty(obj.ActiveSessionId) && obj.Sessions.isKey(obj.ActiveSessionId)
                session = obj.Sessions(obj.ActiveSessionId);
            end
        end

        function tabId = getActiveSessionId(obj)
            %GETACTIVESESSIONID Get the ID of the currently active session
            %
            %   tabId = getActiveSessionId(obj)

            tabId = obj.ActiveSessionId;
        end

        function updateSession(obj, tabId, data)
            %UPDATESESSION Update session data
            %
            %   updateSession(obj, tabId, data)
            %
            %   tabId: The tab/session ID to update
            %   data: Struct with fields to update

            if isempty(tabId) || ~obj.Sessions.isKey(tabId)
                return;
            end

            session = obj.Sessions(tabId);

            % Update provided fields
            if isfield(data, 'messageCount')
                session.messageCount = data.messageCount;
            end

            session.lastActiveAt = now;
            obj.Sessions(tabId) = session;
        end

        function count = getSessionCount(obj)
            %GETSESSIONCOUNT Get the number of active sessions
            %
            %   count = getSessionCount(obj)

            count = obj.Sessions.Count;
        end

        function ids = getAllSessionIds(obj)
            %GETALLSESSIONIDS Get all session IDs
            %
            %   ids = getAllSessionIds(obj)

            ids = obj.Sessions.keys();
        end
    end
end

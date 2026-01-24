classdef ExecutionPolicy
    %EXECUTIONPOLICY Defines code execution policy settings
    %
    %   This enumeration defines the available execution policy modes.

    enumeration
        Auto        % Automatically execute all code
        Prompt      % Prompt user before execution
        Disabled    % Never execute code automatically
    end

    methods
        function tf = requiresApproval(obj)
            %REQUIRESAPPROVAL Check if this policy requires user approval

            tf = (obj == derivux.config.ExecutionPolicy.Prompt);
        end

        function tf = isEnabled(obj)
            %ISENABLED Check if execution is enabled

            tf = (obj ~= derivux.config.ExecutionPolicy.Disabled);
        end
    end
end

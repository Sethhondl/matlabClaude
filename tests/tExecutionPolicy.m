classdef tExecutionPolicy < matlab.unittest.TestCase
    %TEXECUTIONPOLICY Unit tests for ExecutionPolicy enumeration
    %
    %   Run tests with:
    %       results = runtests('tExecutionPolicy');

    properties (TestParameter)
        % All enum values for parameterized tests
        EnumValues = struct(...
            'Auto', claudecode.config.ExecutionPolicy.Auto, ...
            'Prompt', claudecode.config.ExecutionPolicy.Prompt, ...
            'Disabled', claudecode.config.ExecutionPolicy.Disabled)
    end

    methods (Test)
        %% Enumeration Existence Tests
        function testAutoEnumExists(testCase)
            %TESTAUTOENUMEXISTS Verify Auto enum value exists

            policy = claudecode.config.ExecutionPolicy.Auto;
            testCase.verifyClass(policy, 'claudecode.config.ExecutionPolicy');
        end

        function testPromptEnumExists(testCase)
            %TESTPROMPTENUMEXISTS Verify Prompt enum value exists

            policy = claudecode.config.ExecutionPolicy.Prompt;
            testCase.verifyClass(policy, 'claudecode.config.ExecutionPolicy');
        end

        function testDisabledEnumExists(testCase)
            %TESTDISABLEDENUMEXISTS Verify Disabled enum value exists

            policy = claudecode.config.ExecutionPolicy.Disabled;
            testCase.verifyClass(policy, 'claudecode.config.ExecutionPolicy');
        end

        function testExactlyThreeEnumValues(testCase)
            %TESTEXACTLYTHREEENUMVALUES Verify only three enum values exist

            mc = ?claudecode.config.ExecutionPolicy;
            enumList = mc.EnumerationMemberList;

            testCase.verifyLength(enumList, 3);
        end

        %% requiresApproval Method Tests
        function testAutoDoesNotRequireApproval(testCase)
            %TESTAUTODOESNOTREQUIREAPPROVAL Verify Auto returns false

            policy = claudecode.config.ExecutionPolicy.Auto;
            testCase.verifyFalse(policy.requiresApproval());
        end

        function testPromptRequiresApproval(testCase)
            %TESTPROMPTREQUIRESAPPROVAL Verify Prompt returns true

            policy = claudecode.config.ExecutionPolicy.Prompt;
            testCase.verifyTrue(policy.requiresApproval());
        end

        function testDisabledDoesNotRequireApproval(testCase)
            %TESTDISABLEDDOESNOTREQUIREAPPROVAL Verify Disabled returns false

            policy = claudecode.config.ExecutionPolicy.Disabled;
            testCase.verifyFalse(policy.requiresApproval());
        end

        %% isEnabled Method Tests
        function testAutoIsEnabled(testCase)
            %TESTAUTOISENABLED Verify Auto returns true

            policy = claudecode.config.ExecutionPolicy.Auto;
            testCase.verifyTrue(policy.isEnabled());
        end

        function testPromptIsEnabled(testCase)
            %TESTPROMPTISALWAYSENABLED Verify Prompt returns true

            policy = claudecode.config.ExecutionPolicy.Prompt;
            testCase.verifyTrue(policy.isEnabled());
        end

        function testDisabledIsNotEnabled(testCase)
            %TESTDISABLEDISNOTENABLED Verify Disabled returns false

            policy = claudecode.config.ExecutionPolicy.Disabled;
            testCase.verifyFalse(policy.isEnabled());
        end

        %% Parameterized Tests for Consistency
        function testEnumIsValidClass(testCase, EnumValues)
            %TESTENUMISVALIDCLASS Verify all enum values are correct class

            testCase.verifyClass(EnumValues, 'claudecode.config.ExecutionPolicy');
        end

        function testRequiresApprovalReturnsLogical(testCase, EnumValues)
            %TESTREQUIRESAPPROVALRETURNSLOGICAL Verify method returns logical

            result = EnumValues.requiresApproval();
            testCase.verifyClass(result, 'logical');
        end

        function testIsEnabledReturnsLogical(testCase, EnumValues)
            %TESTISENABLEDRETURNSLOGICAL Verify method returns logical

            result = EnumValues.isEnabled();
            testCase.verifyClass(result, 'logical');
        end

        %% Mutual Exclusivity Tests
        function testOnlyPromptRequiresApproval(testCase)
            %TESTONLYPROMPTREQUIRESAPPROVAL Verify only Prompt requires approval

            auto = claudecode.config.ExecutionPolicy.Auto;
            prompt = claudecode.config.ExecutionPolicy.Prompt;
            disabled = claudecode.config.ExecutionPolicy.Disabled;

            approvalRequired = [auto.requiresApproval(), ...
                               prompt.requiresApproval(), ...
                               disabled.requiresApproval()];

            testCase.verifyEqual(sum(approvalRequired), 1, ...
                'Exactly one policy should require approval');
            testCase.verifyTrue(prompt.requiresApproval(), ...
                'That policy should be Prompt');
        end

        function testOnlyDisabledIsNotEnabled(testCase)
            %TESTONLYDISABLEDISNOTENABLED Verify only Disabled is not enabled

            auto = claudecode.config.ExecutionPolicy.Auto;
            prompt = claudecode.config.ExecutionPolicy.Prompt;
            disabled = claudecode.config.ExecutionPolicy.Disabled;

            isEnabled = [auto.isEnabled(), ...
                        prompt.isEnabled(), ...
                        disabled.isEnabled()];

            testCase.verifyEqual(sum(~isEnabled), 1, ...
                'Exactly one policy should be disabled');
            testCase.verifyFalse(disabled.isEnabled(), ...
                'That policy should be Disabled');
        end
    end
end

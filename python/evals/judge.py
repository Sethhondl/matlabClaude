"""
Claude-as-judge implementation for semantic evaluation of agent responses.

Uses the Claude CLI for authentication, avoiding the need for a separate API key.
"""

import asyncio
import json
import os
import shutil
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from .config import EvalConfig, DEFAULT_CONFIG


def find_claude_cli() -> Optional[str]:
    """Find the Claude CLI executable."""
    paths_to_check = [
        shutil.which('claude'),
        os.path.expanduser('~/.claude/local/claude'),
        '/usr/local/bin/claude',
    ]

    nvm_dir = os.path.expanduser('~/.nvm/versions/node')
    if os.path.isdir(nvm_dir):
        for version in sorted(os.listdir(nvm_dir), reverse=True):
            paths_to_check.append(os.path.join(nvm_dir, version, 'bin', 'claude'))

    for path in paths_to_check:
        if path and os.path.isfile(path) and os.access(path, os.X_OK):
            return path

    return None


@dataclass
class CriterionScore:
    """Score for a single evaluation criterion."""
    criterion: str
    passed: bool
    score: float  # 0.0 to 1.0
    reasoning: str


@dataclass
class JudgmentResult:
    """Result of judging an agent response."""
    passed: bool
    score: float  # 0.0 to 1.0 overall score
    reasoning: str
    criteria_scores: List[CriterionScore] = field(default_factory=list)
    suggestions: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "passed": self.passed,
            "score": self.score,
            "reasoning": self.reasoning,
            "criteria_scores": [
                {
                    "criterion": cs.criterion,
                    "passed": cs.passed,
                    "score": cs.score,
                    "reasoning": cs.reasoning
                }
                for cs in self.criteria_scores
            ],
            "suggestions": self.suggestions
        }


JUDGE_PROMPT_TEMPLATE = """You are an expert evaluator for a MATLAB/Simulink AI assistant. Your job is to evaluate a response against specific evaluation criteria.

## User Prompt
{prompt}

## Assistant Response
{response}

## Tools Used
{tools_used}

## Evaluation Criteria
{criteria}

For each criterion, determine:
- Whether it was satisfied (true/false)
- A score from 0.0 to 1.0 (1.0 = fully satisfied, 0.0 = not at all)
- Brief reasoning for your assessment

Be objective and precise. Focus on whether the response actually meets each criterion.

Respond with ONLY valid JSON in this exact format (no other text):
{{
  "criteria_scores": [
    {{
      "criterion": "<the criterion text>",
      "passed": true,
      "score": 0.9,
      "reasoning": "<brief explanation>"
    }}
  ],
  "overall_reasoning": "<summary of the evaluation>",
  "suggestions": []
}}"""


class ClaudeJudge:
    """Uses Claude CLI to evaluate agent responses semantically."""

    def __init__(self, config: Optional[EvalConfig] = None):
        """Initialize the judge.

        Args:
            config: Evaluation configuration. Uses default if None.
        """
        self.config = config or DEFAULT_CONFIG
        self._cli_path = find_claude_cli()

    async def _call_cli(self, prompt: str) -> str:
        """Call Claude CLI with a prompt and return the response."""
        if not self._cli_path:
            raise RuntimeError("Claude CLI not found")

        process = await asyncio.create_subprocess_exec(
            self._cli_path,
            '--print', prompt,
            '--output-format', 'text',
            '--dangerously-skip-permissions',
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={**os.environ, 'CLAUDE_CODE_ENTRYPOINT': 'evals-judge'}
        )

        stdout, stderr = await asyncio.wait_for(
            process.communicate(),
            timeout=60
        )

        response = stdout.decode('utf-8', errors='replace').strip()

        if process.returncode != 0:
            error = stderr.decode('utf-8', errors='replace').strip()
            raise RuntimeError(f"CLI error: {error}")

        return response

    def _call_cli_sync(self, prompt: str) -> str:
        """Synchronous wrapper for CLI call."""
        return asyncio.get_event_loop().run_until_complete(self._call_cli(prompt))

    async def evaluate(
        self,
        prompt: str,
        response: str,
        criteria: List[str],
        tools_used: Optional[List[str]] = None
    ) -> JudgmentResult:
        """Evaluate an agent response against criteria.

        Args:
            prompt: The original user prompt.
            response: The agent's response text.
            criteria: List of evaluation criteria strings.
            tools_used: Optional list of tool names that were called.

        Returns:
            JudgmentResult with scores and reasoning.
        """
        # Format criteria as numbered list
        criteria_text = "\n".join(f"{i+1}. {c}" for i, c in enumerate(criteria))

        # Format tools used
        tools_text = ", ".join(tools_used) if tools_used else "None"

        # Build the judge prompt
        judge_prompt = JUDGE_PROMPT_TEMPLATE.format(
            prompt=prompt,
            response=response,
            tools_used=tools_text,
            criteria=criteria_text
        )

        try:
            # Call Claude CLI
            response_text = await self._call_cli(judge_prompt)

            # Extract JSON from response (handle markdown code blocks)
            json_text = response_text
            if "```json" in json_text:
                json_text = json_text.split("```json")[1].split("```")[0]
            elif "```" in json_text:
                json_text = json_text.split("```")[1].split("```")[0]

            result_data = json.loads(json_text.strip())

            # Build criterion scores
            criteria_scores = []
            for cs_data in result_data.get("criteria_scores", []):
                criteria_scores.append(CriterionScore(
                    criterion=cs_data.get("criterion", ""),
                    passed=cs_data.get("passed", False),
                    score=cs_data.get("score", 0.0),
                    reasoning=cs_data.get("reasoning", "")
                ))

            # Calculate overall score (average of criterion scores)
            if criteria_scores:
                overall_score = sum(cs.score for cs in criteria_scores) / len(criteria_scores)
            else:
                overall_score = 0.0

            # Determine pass/fail
            passed = overall_score >= self.config.pass_threshold

            return JudgmentResult(
                passed=passed,
                score=overall_score,
                reasoning=result_data.get("overall_reasoning", ""),
                criteria_scores=criteria_scores,
                suggestions=result_data.get("suggestions", [])
            )

        except json.JSONDecodeError as e:
            return JudgmentResult(
                passed=False,
                score=0.0,
                reasoning=f"Failed to parse judge response as JSON: {e}",
                criteria_scores=[],
                suggestions=[]
            )
        except Exception as e:
            return JudgmentResult(
                passed=False,
                score=0.0,
                reasoning=f"Unexpected error during evaluation: {e}",
                criteria_scores=[],
                suggestions=[]
            )

    def evaluate_tool_usage(
        self,
        tools_used: List[str],
        required_tools: List[str],
        forbidden_tools: List[str]
    ) -> CriterionScore:
        """Evaluate tool usage against expectations.

        This is a deterministic check, not using Claude.

        Args:
            tools_used: List of tool names that were called.
            required_tools: Tools that must be used.
            forbidden_tools: Tools that must NOT be used.

        Returns:
            CriterionScore for tool usage.
        """
        # Normalize tool names (handle mcp__ prefix)
        def normalize_tool(t: str) -> str:
            if "__" in t:
                parts = t.split("__")
                return parts[-1]
            return t

        used_normalized = set(normalize_tool(t) for t in tools_used)
        required_normalized = set(normalize_tool(t) for t in required_tools)
        forbidden_normalized = set(normalize_tool(t) for t in forbidden_tools)

        # Check required tools
        missing_required = required_normalized - used_normalized
        used_forbidden = used_normalized & forbidden_normalized

        issues = []
        if missing_required:
            issues.append(f"Missing required tools: {', '.join(missing_required)}")
        if used_forbidden:
            issues.append(f"Used forbidden tools: {', '.join(used_forbidden)}")

        if issues:
            return CriterionScore(
                criterion="Tool usage requirements",
                passed=False,
                score=0.0,
                reasoning="; ".join(issues)
            )

        return CriterionScore(
            criterion="Tool usage requirements",
            passed=True,
            score=1.0,
            reasoning="All tool usage requirements met"
        )

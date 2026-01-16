"""Setup script for claudecode Python package."""

from setuptools import setup, find_packages

setup(
    name="claudecode",
    version="0.1.0",
    description="Claude Code MATLAB Integration - Python Core",
    author="Your Name",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=[],
    extras_require={
        "dev": ["pytest", "black", "mypy"],
    },
)

#!/usr/bin/env python3
"""Run native checks and expose actionable failures in GitHub's check summary."""
import json
from pathlib import Path
import subprocess
import sys

device = sys.argv[1]
result_path = Path('build/CI.xcresult')
result_path.parent.mkdir(exist_ok=True)
command = ['xcodebuild', '-quiet', '-project', 'HeartAdoption.xcodeproj', '-scheme', 'HeartAdoption',
           '-destination', f'platform=iOS Simulator,id={device}', '-parallel-testing-enabled', 'NO',
           '-resultBundlePath', str(result_path), 'test']
result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
print(result.stdout)
if result.returncode:
    details = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result_path), '--format', 'json'], capture_output=True, text=True)
    try:
        summary = json.loads(details.stdout)
        messages = [f"{failure.get('testIdentifierString', '')}: {failure['failureText']}" for failure in summary.get('testFailures', [])]
    except (ValueError, KeyError):
        messages = []
    if not messages:
        messages = [line for line in result.stdout.splitlines() if 'error:' in line.lower() or 'Testing failed:' in line]
    for message in messages or [result.stdout[-5000:]]:
        escaped = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f'::error title=iOS verification failed::{escaped}')
sys.exit(result.returncode)

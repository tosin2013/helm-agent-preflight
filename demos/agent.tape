# helm-agent-preflight — AI agent session demo
# Shows OpenCode / simulated agent using SKILL.md protocol:
#   RBAC escalation → BLOCK → agent proposes fix → PASS → human authorizes
# Run:  vhs demos/agent.tape
# Needs: bin/preflight-linux-amd64, conftest in PATH

Output demos/agent.gif

Set Width 160
Set Height 50
Set FontSize 13
Set Theme "Dracula"
Set TypingSpeed 30ms
Set CursorBlink false

Hide
  export PATH="/home/vpcuser/bin:/usr/local/bin:$PATH"
  cd /home/vpcuser/helm-agent-preflight
Show

Sleep 500ms
Type "bash demo-agent.sh"
Enter
# demo-agent.sh runs ~20-25s (two preflight invocations + formatting)
Sleep 35s

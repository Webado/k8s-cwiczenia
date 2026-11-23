# Hook PreToolUse dla Claude Code: "strażnik GitOps".
# Claude Code przed każdym wywołaniem narzędzia Bash/PowerShell przekazuje tu (na stdin) JSON:
#   { "tool_name": "Bash", "tool_input": { "command": "kubectl scale ..." }, ... }
# Jeśli wypiszemy JSON z permissionDecision = "deny", Claude Code NIE wykona komendy,
# a powód (permissionDecisionReason) trafi do Claude'a, który dostosuje plan.
#
# UWAGA: hook pilnuje tylko komend wykonywanych PRZEZ CLAUDE'A. Twojego terminala nie dotyka.

[Console]::InputEncoding  = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$data = [Console]::In.ReadToEnd() | ConvertFrom-Json
$cmd  = [string]$data.tool_input.command
if (-not $cmd) { exit 0 }

function Deny([string]$reason) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Compress -Depth 5
    exit 0
}

# Reguła 1: kubectl/helm tylko na lokalnym klastrze
if ($cmd -match '\b(kubectl|helm)\b.*--(kube-)?context[ =]"?([^\s"]+)') {
    if ($Matches[3] -ne 'docker-desktop') {
        Deny "Zablokowane przez hook gitops-guard: komenda wskazuje kontekst '$($Matches[3])'. W tym repo wolno pracować tylko na lokalnym klastrze 'docker-desktop'."
    }
}

# Reguła 2: namespace'y zarządzane przez Argo CD zmieniamy TYLKO przez git
$kubectlZmiana = '\bkubectl\b.*\b(apply|create|edit|patch|replace|scale|delete|set|label|annotate|autoscale|rollout\s+(restart|undo))\b'
$helmZmiana    = '\bhelm\b.*\b(install|upgrade|uninstall|rollback)\b'
$nsArgo        = '(-n|--namespace)[ =]"?(staging|production|argocd)\b'

if (($cmd -match $kubectlZmiana -or $cmd -match $helmZmiana) -and $cmd -match $nsArgo) {
    $ns = $Matches[2]
    Deny ("Zablokowane przez hook gitops-guard: namespace '$ns' jest zarządzany przez Argo CD (GitOps). " +
          "Ręczna zmiana zostałaby cofnięta przez self-heal albo zrobiłaby OutOfSync. " +
          "Zamiast tego: zmień plik w 02-helm-argo/chart/values-*.yaml na nowym branchu, wypchnij go i otwórz PR (gh pr create). " +
          "Komendy tylko do odczytu (get, describe, logs, top) są dozwolone.")
}

exit 0

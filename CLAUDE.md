# CLAUDE.md: repo ćwiczeniowe K8s / Helm / Argo CD / Terraform / Docker

Repo do nauki przed rolą Senior Platform Developer (L3 support). Lekcje w folderach, każda ma `README.md` z zadaniami.
Odpowiadaj po polsku. Użytkownik się uczy: tłumacz *dlaczego*, nie tylko *co*, i nie rozwiązuj zadań, o które nie prosił.

## Struktura
- `01-k8s-podstawy/`: manifesty + `awarie/` (namespace `lekcja1`, `awarie`)
- `02-helm-argo/`: `chart/` (Helm, `values-staging.yaml`, `values-production.yaml`), `argocd/` (Applications)
- `03-skalowanie/`: zasoby, HPA, rollouty (namespace `lekcja3`)
- `04-terraform/`: `local/` (providery kubernetes/helm na lokalnym klastrze), `aws-review/` (TYLKO do czytania, nigdy `apply`)
- `05-docker-obrazy/`: `app/` (zły Dockerfile), `rozwiazanie/` (multi-stage)
- `06-final/`: incydenty (`incydenty`, `incydenty-sklep`), `_scenariusze/`, `post-mortem.md`
- Pliki `ROZWIAZANIA.md` i `_scenariusze/` to spoilery: nie czytaj ich, dopóki użytkownik nie skończy diagnozy albo nie poprosi.

## Środowisko i zasady bezpieczeństwa
- Jedyny dozwolony kontekst: `docker-desktop`. Przed pierwszą komendą kubectl/helm sprawdź `kubectl config current-context`.
- `staging`, `production`, `argocd` są zarządzane przez Argo CD (repo na GitHubie, gałąź `main`, path `02-helm-argo/chart`).
  - `demo-staging`: auto-sync + selfHeal (ręczna zmiana kubectl-em zostanie cofnięta).
  - `demo-production`: bez auto-sync, wdrożenie ręcznym Sync w Argo.
  - Zmiany tylko przez git: branch → zmiana w `values-*.yaml` → push → `gh pr create`. **Nigdy nie merguj PR-ów**, to robi użytkownik.
- Namespace'y „do zabawy” (wolno `kubectl apply/delete`): `lekcja1`, `lekcja3`, `awarie`, `incydenty`, `incydenty-sklep`, `tf-*`.
- Diagnoza zawsze najpierw tylko do odczytu (`get`, `describe`, `logs`, `top`, `events`). Poprawka dopiero po zgodzie użytkownika.
- Hook `.claude/hooks/gitops-guard.ps1` twardo blokuje część z tych reguł. Gdy zablokuje, nie obchodź go, tylko przejdź na ścieżkę git/PR.

## Sprawdzanie zmian przed commitem
- Helm: `helm lint 02-helm-argo/chart -f 02-helm-argo/chart/values-staging.yaml` oraz `helm template ...`, żeby zobaczyć wynikowy YAML.
- Manifesty: `kubectl apply --dry-run=server -f <plik>`.
- Terraform (`04-terraform/local`): `terraform fmt`, `terraform validate`, `terraform plan`. `apply` tylko po przeczytaniu planu z użytkownikiem, bez `-auto-approve`.

## Konwencje
- Commity po polsku, krótko, w trybie „co zmienia”: `Lekcja 06: ...` dla materiałów, opisowo dla zmian na stagingu.
- Pliki w LF (`.gitattributes`: `eol=lf`), kodowanie UTF-8.
- Sekrety i state nie trafiają do gita: `*.tfstate`, `.terraform/`, `.claude/settings.local.json`.

## Znane pułapki (Windows)
- PowerShell 5.1: `>` i `Out-File` zapisują UTF-16, a `Set-Content` w ANSI. Używaj `-Encoding utf8`.
- PowerShell + Terraform: argumenty z `=` w cudzysłowie, np. `terraform plan "-var-file=staging.tfvars"`.
- PowerShell 5.1 nie zna `&&`/`||`: używaj `; if ($?) { ... }`.
- Git Bash przerabia ścieżki typu `/sys/...` na `C:/Program Files/Git/...`: przy `kubectl exec` dodaj `MSYS_NO_PATHCONV=1`.
- ConfigMapa użyta jako env nie trafia do działających podów: potrzebny `kubectl rollout restart`.

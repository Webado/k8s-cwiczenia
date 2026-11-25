# Ściąga na pierwszy tydzień: Platform Dev / L3 support

> Skrót z lekcji 01–06. Do trzymania otwartego obok terminala.

## 0. Pięć zasad, które ratują skórę
1. **Sprawdź kontekst, zanim cokolwiek wpiszesz.** `kubectl config current-context`. Na produkcji pierwsze dni pracuj tylko do odczytu.
2. **Najpierw przywróć działanie, potem naprawiaj porządnie.** Limit w górę, ręczne odpalenie joba, rollback. Refaktor to osobny ticket, na spokojnie, z testami.
3. **Zamknij pętlę.** Zmergowane ≠ wdrożone ≠ naprawione. Ticket zamykasz, gdy **objaw zniknął** (logi, odpowiedź HTTP, Argo `Synced` + `Healthy`), a nie gdy zmieniłeś YAML-a.
4. **Udowodnij, nie zgaduj.** „Service nazywa się chyba `rabbitmq`” → `kubectl get svc`. Każde twierdzenie w diagnozie ma komendę i wynik.
5. **Klaster zarządzany przez Argo zmieniasz przez gita.** `kubectl edit` na stagingu zostanie cofnięte (selfHeal), a na produkcji zrobi drift, o którym nikt nie wie.

---

## 1. Pierwsze dni: checklista
- [ ] Dostępy: AWS (SSO), kubeconfig do EKS, Argo CD (SSO), Kibana, Sentry, monitoring, RabbitMQ Management.
- [ ] `aws eks update-kubeconfig --name <klaster> --alias <czytelna-nazwa>`, potem `kubectl config get-contexts`.
- [ ] `kubectl auth can-i --list -n <ns>`: co właściwie wolno Ci zrobić?
- [ ] Przeczytaj `CLAUDE.md` i README w repo aplikacji, chartów Helm i Terraforma. Jeśli `CLAUDE.md` nie ma, masz pierwszy wartościowy PR.
- [ ] Narysuj sobie mapę: które repo → który chart → która Application w Argo → który namespace.
- [ ] Pytania do zespołu:
  - Jak wygląda deploy na produkcję (auto-sync czy ręczny Sync)? Kto go zatwierdza?
  - Kto i gdzie robi `terraform apply` (lokalnie, CI, Atlantis)? Gdzie jest state?
  - Są runbooki i alerty? Gdzie są post-mortemy? Jak wygląda dyżur?
  - Jakie hooki, skille i MCP do Claude Code już macie?

---

## 2. Objaw → pierwsza komenda
| Objaw | Komenda | Na co patrzeć |
|---|---|---|
| `CrashLoopBackOff` | `kubectl logs <pod> --previous` | błąd aplikacji, zła konfiguracja (DNS, host, hasło) |
| restarty, exit **137** | `kubectl describe pod` → `Last State` | `OOMKilled`: limit pamięci vs rzeczywiste zużycie |
| `Pending` | `kubectl describe pod` → Events | `Insufficient cpu/memory` (requests > wolne zasoby na nodach) |
| `ImagePullBackOff` | `kubectl describe pod` | zły tag, brak uprawnień do ECR |
| `CreateContainerConfigError` | `kubectl describe pod` | brakujący ConfigMap/Secret albo klucz w nim |
| `Running`, ale `0/1` | `describe pod` (Readiness), `logs` | probe pyta o zły port lub ścieżkę, aplikacja nie wstaje |
| pod `Ready`, a ruch nie dochodzi | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` | selector Service'u vs labele, `port`/`targetPort` |
| mniej replik niż powinno | `kubectl describe rs <rs>` → Events | `FailedCreate: exceeded quota`, potem HPA (`kubectl get hpa`) |
| wolno, bez błędów | `kubectl exec <pod> -- cat /sys/fs/cgroup/cpu.stat` | `nr_throttled / nr_periods` (`kubectl top` uśrednia i kłamie) |
| nowa wersja nie wchodzi | `kubectl rollout status deploy/<x>`, `kubectl get rs` | dwa ReplicaSety, nowy `READY 0`, `ProgressDeadlineExceeded` |
| CronJob „nie działa” | `kubectl get cronjob,jobs`, `describe job` | `suspend`, OOM, `backoffLimit`, `concurrencyPolicy` |

Zawsze na koniec: `kubectl get events -n <ns> --sort-by=.lastTimestamp`.
Ręczne odpalenie CronJoba: `kubectl create job --from=cronjob/<nazwa> <nazwa>-reczny -n <ns>`.

---

## 3. Argo CD
| Status | Znaczy |
|---|---|
| `Synced` / `OutOfSync` | czy klaster zgadza się z gitem |
| `Healthy` / `Progressing` / `Degraded` / `Missing` | czy to, co wdrożone, działa |
| `OutOfSync` + `Healthy` | **cicha awaria**: stara wersja działa, nowa nie weszła (sprawdź operację!) |

- **Refresh** = „przeczytaj gita jeszcze raz”. **Sync** = „wdróż”. To dwie różne rzeczy.
- Sync utknął na starej rewizji (np. na zepsutym commicie): **Terminate** operacji, potem nowy sync.
  `kubectl get application <app> -n argocd -o jsonpath='{.status.operationState.message}'`
- Ręczny Sync na produkcji: najpierw **App Diff**, a usuwanie zasobów tylko z zaznaczonym **Prune**.
- Rollback przy auto-syncu: `git revert` + PR. Przycisk History/Rollback w Argo jest przy auto-syncu wyłączony.
- Argo widzi **tylko to, co jest w gicie na właściwej gałęzi**. Niezacommitowane `values-*.yaml` nic nie robią.
- Skalowanie: przy włączonym HPA `replicaCount` jest ignorowany. Zmieniasz `autoscaling.minReplicas`.

## 4. Helm
```bash
helm lint <chart> -f values-<env>.yaml
helm template <release> <chart> -f values-<env>.yaml > /tmp/out.yaml   # wynikowy YAML: to naprawdę idzie na klaster
```
- Hierarchia: `values.yaml` (domyślne) ← `values-<env>.yaml` (nadpisania). Szukaj najpierw w pliku środowiska.
- Annotation `checksum/config` w Deploymencie = zmiana ConfigMapy wymusza rollout.

## 5. Skalowanie: kto co dokłada
| Mechanizm | Dokłada | Na podstawie |
|---|---|---|
| HPA | **pody** | % CPU/pamięci względem `requests` |
| KEDA | **pody** (także od 0) | długość kolejki RabbitMQ, lag itd. |
| Cluster Autoscaler / Karpenter | **nody (EC2)** | pody w `Pending` z `Insufficient ...` |
| ResourceQuota | **blokuje** | suma `requests` w namespace. Pod **w ogóle nie powstaje**, nie ma `Pending` |

---

## 6. Terraform: review i praca
- `plan`: `+` tworzy, `~` zmienia w miejscu, `-` usuwa, **`-/+` = forces replacement** (przy bazie danych to czerwona lampka).
- Nigdy `apply` bez przeczytanego planu. Najbezpieczniej `plan -out=tfplan`, a potem `apply tfplan`.
- Na co patrzeć w review:
  - `publicly_accessible`, `0.0.0.0/0`, publiczny endpoint EKS,
  - IAM `"*"` (zwłaszcza na roli noda zamiast IRSA/Pod Identity), hasła w kodzie,
  - `deletion_protection`, backupy, `prevent_destroy`, wersjonowanie S3, `force_destroy`,
  - stara wersja K8s, node group `min = max`.
- State: remote (S3 + lock), **zawiera sekrety**, nigdy do gita.
- Drift: ktoś zmienił coś ręcznie, więc `plan` pokaże, że chce to cofnąć. Najpierw ustal, czyja zmiana jest właściwa.
- `helm_release` nie widzi ręcznych zmian w zasobach, które wdrożył (np. `kubectl scale`).

## 7. Odchudzanie obrazów i wolne środowisko lokalne
- **Multi-stage:** narzędzia buildowe (composer, gcc, dev-deps) zostają w stage'u `vendor`/`build`, nie w obrazie produkcyjnym.
- **Kolejność warstw:** najpierw `composer.json` + `composer.lock` → `composer install`, dopiero potem `COPY . .` (cache!).
- **`.dockerignore` w katalogu kontekstu buildu:** `vendor/`, `var/`, `.git/`, `node_modules/`.
- **Prod:** `--no-dev --optimize-autoloader`, `php.ini-production`, opcache, bez xdebug, `display_errors=0`.
- **Szybszy build:** BuildKit `--mount=type=cache` na cache composera/apt. `apt-get update && install ... && rm -rf /var/lib/apt/lists/*` w **jednym** `RUN`.
- **Diagnoza:** `docker history <obraz>`, `docker images`, narzędzie `dive`.
- **Sygnały:** `exec` w entrypoincie (PID 1 dostaje SIGTERM). Obraz `php:apache` ma `STOPSIGNAL SIGWINCH`, więc worker CLI potrzebuje `STOPSIGNAL SIGTERM`.

## 8. PHP / RabbitMQ / Elasticsearch na K8s
- `memory_limit` w PHP **trochę poniżej** limitu poda: dostaniesz czytelny błąd w Sentry zamiast cichego OOMKill.
- Workery (Symfony Messenger): `messenger:consume --time-limit=3600 --memory-limit=200M`, obsługa SIGTERM, a `terminationGracePeriodSeconds` dłuższy niż najdłuższa wiadomość.
- Web przy rolloucie: `preStop: sleep 5–10`, żeby pod zdążył zniknąć z endpointów, zanim Apache/FPM się zamknie (inaczej `Connection refused`/502).
- RabbitMQ:
  - `rabbitmqctl list_queues name messages consumers`: `consumers 0` znaczy, że workery leżą,
  - rosnące `messages` znaczy, że workerów jest za mało (KEDA),
  - memory alarm (watermark) blokuje **publisherów**.
- Elasticsearch:
  - `GET _cluster/health`: `yellow` = brak replik, `red` = brak primary shardów,
  - dysk powyżej 95% (flood stage) ustawia indeksy w read-only.

---

## 9. Claude Code w pracy
- **CLAUDE.md = prośba** (model zwykle słucha). **Hook = twarda blokada** (deterministyczna). Zasada: „nigdy” idzie do hooka.
- Hook dopasowuje **tekst, nie intencję**. Bywa fałszywy alarm (blokada komendy, która tylko zawiera słowo `destroy`), da się go też obejść (np. zmienną `TF_CLI_ARGS`). To barierka, nie zabezpieczenie.
- Review PR-a od AI:
  1. Czy diff robi to, co mówi opis, i **nic więcej**?
  2. Czy AI coś sprawdziło (`helm template`, `lint`, `plan`), czy tylko twierdzi?
  3. Czy poprawka leczy przyczynę, czy objaw (limit w górę vs wyciek pamięci)?
  4. **Po merge'u: czy to weszło?** (Argo, rollout, objaw). Tego AI za Ciebie nie zrobi.
- Prompt do diagnozy: *„Ticket: <objaw>. Namespace <ns>, kontekst <ctx>. Tylko do odczytu. Podaj objaw → przyczynę → dowód (komenda + wynik) → poprawkę doraźną i trwałą. Nie naprawiaj bez mojej zgody.”*

## 10. Incydent i post-mortem
1. **Potwierdź objaw** (sam go zobacz) → 2. **Ustabilizuj** (rollback / limit / skala) → 3. **Zakomunikuj** status →
4. **Przyczyna** z dowodem → 5. **Poprawka trwała** przez PR → 6. **Zweryfikuj, że objaw zniknął** → 7. post-mortem.
- Post-mortem bez szukania winnych: „nic nie złapało błędu przed produkcją”, a nie „Kowalski się pomylił”.
- Zawsze odpowiedz też na pytanie: **dlaczego nikt tego nie zauważył** (brak alertu, pipeline nie czeka na rollout).
- Każde działanie naprawcze ma **właściciela i termin**.

---

## 11. Pułapki, na które trafiłeś w kursie
- Zielony pod ≠ naprawiony objaw. Zmergowany PR ≠ wdrożony (Argo potrafi wisieć na starej rewizji).
- Wpisanie wartości „na pamięć” zamiast sprawdzenia w klastrze (nazwa Service'u).
- Refaktor w trakcie pożaru zamiast szybkiego przywrócenia działania (raport dla banku).
- `kubectl top` jako dowód na „zasobów wystarczy” przy throttlingu CPU.
- Komenda w złym namespace (zapomniane `-n`): „nic się nie stało”, bo nic nie trafiło tam, gdzie miało.
- Obraz ≠ kontener (`docker stop <nazwa kontenera>`, a nie obrazu).
- Pod scaling (HPA/KEDA) ≠ node scaling (Cluster Autoscaler/Karpenter).

## 12. Windows / PowerShell 5.1
- `>` i `Out-File` zapisują UTF-16 (git widzi plik jako binarny), więc `| Out-File -Encoding utf8`.
- Brak `&&`: `cmd1; if ($?) { cmd2 }`.
- Terraform: `terraform plan "-var-file=prod.tfvars"` (w cudzysłowie).
- Git Bash przy `kubectl exec ... /sys/...`: `MSYS_NO_PATHCONV=1`.
- Base64 z Secretu: `[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))`.

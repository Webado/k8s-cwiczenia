---
name: diagnoza-k8s
description: Systematyczna diagnoza problemu z aplikacją w Kubernetesie (pod nie wstaje, restartuje się, nie odpowiada, działa wolno, za mało replik, zadanie CronJob się nie wykonuje, nowa wersja nie wchodzi). Używaj, gdy użytkownik opisuje objaw z klastra K8s albo wkleja zgłoszenie od supportu i prosi o znalezienie przyczyny.
---

# Diagnoza incydentu w Kubernetesie

Prowadzisz diagnozę jak doświadczony inżynier on-call. Cel: znaleźć **przyczynę** (a nie tylko objaw)
i udowodnić ją wynikiem komendy.

## Zasady bezpieczeństwa (bezwzględne)

1. Na początku ZAWSZE sprawdź kontekst: `kubectl config current-context`. Jeśli to nie jest `docker-desktop`,
   zatrzymaj się i zapytaj użytkownika.
2. Podczas diagnozy używaj WYŁĄCZNIE komend do odczytu: `get`, `describe`, `logs`, `top`, `events`,
   `exec ... cat/env/curl/wget` (bez modyfikacji czegokolwiek).
3. Niczego nie naprawiaj bez wyraźnej zgody użytkownika. Najpierw raport, potem propozycja.
4. Namespace'y `staging`, `production`, `argocd` są zarządzane przez Argo CD: poprawka TYLKO przez zmianę
   w repo (branch + PR), nigdy przez kubectl.

## Procedura

Przechodź po kolei. Przy każdym kroku zapisuj, co wykluczyłeś.

1. **Zakres:** `kubectl get all,cronjob,job,hpa,resourcequota -n <ns>`. Co jest niezdrowe?
   Zwróć uwagę na READY (np. `0/1`), STATUS, RESTARTS i na Deploymenty, gdzie READY < oczekiwane.
2. **Pody, które nie działają:** `kubectl describe pod <pod> -n <ns>`:
   - sekcja **Events** (na dole): ImagePull, FailedScheduling, probe failed, FailedMount,
   - **Last State / Reason / Exit Code**: 137 = SIGKILL (OOMKilled albo przekroczony grace period), 1 = błąd aplikacji, 0 = proces się zakończył,
   - `kubectl logs <pod> -n <ns> --previous`: logi z POPRZEDNIEGO (padniętego) kontenera.
3. **Pody, których brakuje** (Deployment chce N, jest mniej, a nie ma Pending):
   `kubectl describe rs -n <ns>` i `kubectl get events -n <ns> --sort-by=.lastTimestamp`: szukaj `FailedCreate`
   (np. `exceeded quota`).
4. **Rollout, który utknął:** `kubectl rollout status deploy/<d> -n <ns>`, `kubectl get rs -n <ns>`:
   ile podów ma stary, a ile nowy ReplicaSet? Dlaczego nowe nie są Ready?
5. **CronJob / Job:** `kubectl get cronjob,job -n <ns>`, `kubectl describe job <job>`, a potem pody joba jak w kroku 2.
6. **Ruch nie dociera:** `kubectl get endpointslices -n <ns>`, porównaj selector Service'u z `--show-labels` podów.
   Sprawdź, czy nazwy hostów w konfiguracji (ConfigMap/env) odpowiadają istniejącym Service'om (`kubectl get svc`).
7. **Wolne działanie:** `kubectl top pod -n <ns>` porównaj z `resources.limits`. Zużycie CPU tuż przy limicie
   = **throttling** (aplikacja nie pada, tylko zwalnia; brak błędów w logach).
8. **Konfiguracja:** `kubectl get configmap <cm> -n <ns> -o yaml` i `kubectl exec ... -- env`. Pamiętaj:
   zmiana ConfigMapy użytej jako env NIE trafia do działających podów bez restartu.
9. **Argo CD** (jeśli namespace jest zarządzany przez Argo): `kubectl get application -n argocd`.
   Sync/Health i wdrożona rewizja vs `git log`.

## Format raportu

Odpowiedz dokładnie w tym formacie:

```
## Diagnoza: <krótki tytuł>

**Objaw:** co widzi użytkownik/klient
**Przyczyna:** jedno-dwa zdania, konkretnie
**Dowód:**
    <komenda>
    <istotny fragment wyniku>
**Poprawka doraźna:** co zrobić teraz (i czy wymaga restartu/rolloutu)
**Poprawka trwała:** zmiana w repo (który plik, jakie pole); dla staging/production: branch + PR
**Jak zapobiec:** monitoring/alert/review/test, który złapałby to wcześniej
```

Jeśli nie masz pewności, napisz to wprost i podaj, jaką następną komendą to rozstrzygniesz.

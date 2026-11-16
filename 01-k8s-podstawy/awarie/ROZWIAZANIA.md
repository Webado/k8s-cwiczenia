# Rozwiązania awarii (spoilery!)

## 1. `sklep`: ImagePullBackOff
- **Objaw:** `0/1 ImagePullBackOff`
- **Diagnoza:** `kubectl describe pod -n awarie -l app=sklep` -> Events: `Failed to pull image "php:8.3-apahce" ... not found`
- **Przyczyna:** literówka w tagu (`apahce`).
- **Poprawka:** `image: php:8.3-apache`
- **W pracy:** częściej powód to brak uprawnień do prywatnego rejestru (ECR, imagePullSecrets / rola IAM noda)
  albo CI nie zdążył/nie zbudował obrazu z danym tagiem.

## 2. `raporty`: OOMKilled -> CrashLoopBackOff
- **Objaw:** status skacze `Running` -> `OOMKilled` -> `CrashLoopBackOff`, RESTARTS rośnie.
- **Diagnoza:** `kubectl describe pod -n awarie -l app=raporty` -> `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`
- **Przyczyna:** proces alokuje ~300 MB, a `limits.memory: 64Mi`.
- **Poprawka:** podnieść limit (np. `512Mi`) **albo**, lepiej, naprawić kod (stream zamiast ładowania wszystkiego do pamięci).
- **W pracy:** OOMKilled NIE pojawi się w Kibanie ani Sentry, bo kernel zabija proces, zanim PHP cokolwiek zaloguje.
  To typowy przypadek „w logach nic nie ma, a się restartuje”.
- Uwaga: `memory_limit` z php.ini i `limits.memory` z K8s to dwie różne rzeczy. Trzeba je ustawić spójnie.

## 3. `api`: Service nie trafia w pody
- **Objaw:** pody `1/1 Running`, ale `kubectl exec ... curl http://api` się nie łączy / port-forward na `svc/api` się sypie.
- **Diagnoza:** `kubectl get endpointslices -n awarie` -> `api-xxxxx  <unset>`, czyli Service nie ma ŻADNYCH endpointów.
  Potem `kubectl get svc api -n awarie -o yaml` (selector: `app: api-v2`) vs `kubectl get pods -n awarie --show-labels` (`app=api`).
- **Przyczyna:** selector Service'u nie pasuje do labeli podów.
- **Poprawka:** `selector: { app: api }`
- **W pracy:** zdarza się przy refaktorze nazw w Helm chartach. Zero błędów, po prostu 503 z Ingressa.

## 4. `mailer`: CreateContainerConfigError
- **Objaw:** `0/1 CreateContainerConfigError`
- **Diagnoza:** `describe` -> Events: `couldn't find key SMTP_PASSWORD in Secret awarie/mailer-secret`
- **Przyczyna:** Secret ma klucz `SMTP_PASS`, a Deployment szuka `SMTP_PASSWORD`.
- **Poprawka:** ujednolicić nazwę klucza (w Secrecie albo w `secretKeyRef.key`).
- **W pracy:** Secret jest w innym namespace (Secrety są per namespace!), External Secrets nie zsynchronizował
  się z AWS Secrets Manager albo ktoś dodał nową zmienną do Deploymentu i zapomniał o Secrecie na prodzie.

## 5. `panel`: Running, ale 0/1 Ready
- **Objaw:** `0/1 Running`, RESTARTS = 0. Pod żyje, ale nie dostaje ruchu.
- **Diagnoza:** `describe` -> Events: `Readiness probe failed: HTTP probe failed with statuscode: 404`
- **Przyczyna:** probe pyta `/healthz`, a taki endpoint nie istnieje.
- **Poprawka:** dodać endpoint health w aplikacji albo poprawić `path` w probe.
- **W pracy:** gdyby to była **liveness**Probe, K8s restartowałby poda w kółko. Błędnie ustawiona liveness
  (np. sprawdzająca bazę danych) potrafi położyć cały system, gdy baza na chwilę zwolni: wszystkie pody restartują się naraz.

---

## Zadanie 3 z README (ConfigMapa się zmieniła, a apka nie)
Zmienne środowiskowe z ConfigMapy są wczytywane **tylko przy starcie kontenera**.
Po zmianie trzeba zrobić `kubectl rollout restart deploy/web -n lekcja1`.
Helm często rozwiązuje to adnotacją z checksumem configu w template poda (zmiana configu = nowy hash = rollout).

## Zadanie 6 z README (problemy produkcyjne w manifestach)
- Secret z hasłem w plain text w repo.
- RabbitMQ jako Deployment bez PersistentVolume: restart = utrata wiadomości. 1 replika = brak HA.
- Brak `limits.cpu` jest OK (to świadoma decyzja wielu zespołów), ale brak PodDisruptionBudget,
  brak anti-affinity (obie repliki `web` mogą wylądować na jednym nodzie) to już ryzyko.
- Kod w ConfigMapie zamiast w obrazie.
- Brak `securityContext` (kontenery chodzą jako root).

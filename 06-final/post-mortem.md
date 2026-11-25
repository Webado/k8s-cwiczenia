# Post-mortem: API v2 nie trafiło do klientów mimo zielonego pipeline'u (Ticket #4)

**Wpływ:**
- Wszyscy klienci API (Service `api`, namespace `incydenty`) dostawali wersję v1, bez zapowiedzianego eksportu do PDF.
- Od wdrożenia v2 do zgłoszenia minął około dzień (w symulacji: od 08:45 do zgłoszenia przez Product Ownera).
- Nie było przestoju: v1 działała poprawnie i obsługiwała 100% ruchu. Problemem była nowa funkcja, która
  nie dotarła na produkcję, a zespół był przekonany, że dotarła.
- Skutek biznesowy: obietnica wobec klientów (eksport PDF) nie została dotrzymana, a zespół przez dobę nie wiedział,
  że wdrożenie się nie udało.

**Oś czasu** (czas lokalny symulacji):
| Czas | Zdarzenie |
|---|---|
| 08:45 | Pipeline robi `kubectl apply` manifestu v2 (nowa ConfigMapa `api-v2` + zmiana Deploymentu). Pipeline kończy się na zielono. |
| 08:45 | Powstaje nowy ReplicaSet `api-5b4cb767f5` z jednym podem v2. Readiness probe od razu zwraca 404 na `/health.php`. |
| 08:55 | Deployment przekracza `progressDeadlineSeconds` (600 s): `ReplicaSet "api-5b4cb767f5" has timed out progressing`. Nikt nie dostaje alertu. |
| następny dzień | **Wykrycie:** Product Owner zgłasza, że klienci nie widzą v2 (Ticket #4). |
| +ok. 10 min | **Diagnoza:** `kubectl get pods` pokazuje pod v2 `0/1`; `kubectl logs` daje `script '/var/www/html/health.php' not found`; `kubectl describe pod` pokazuje `Readiness probe failed ... statuscode: 404` (x1016). Wejście do poda (`exec`) potwierdza brak pliku. Porównanie ConfigMap: `api-v1` ma `health.php` i `index.php`, `api-v2` ma tylko `index.php`. |
| (do uzupełnienia) | **Poprawka:** dodanie `health.php` do ConfigMapy `api-v2`, `kubectl apply`, `kubectl rollout restart deploy/api`. |
| (do uzupełnienia) | **Potwierdzenie:** `kubectl rollout status deploy/api -n incydenty` kończy się sukcesem, a `kubectl exec -n incydenty ruch -- wget -q -O- http://api/` zwraca `"version":"v2"` z kilku różnych podów. |

**Przyczyna źródłowa (5 x dlaczego):**
1. *Dlaczego klienci dostawali v1?* Ruch nadal obsługiwały 3 stare pody v1. Pod v2 nie był Ready, więc nie trafił
   do endpointów Service'u.
2. *Dlaczego pod v2 nie był Ready?* Readiness probe pyta o `/health.php`, a w podzie v2 nie było tego pliku (HTTP 404).
3. *Dlaczego nie było pliku?* Kod v2 przygotowano jako nową ConfigMapę `api-v2`, w której znalazł się tylko `index.php`.
   Plik `health.php` istniał w v1 jako osobny element, nie był częścią „kodu aplikacji” i przy przygotowaniu v2 wypadł.
   Kontrakt „aplikacja musi wystawiać endpoint health” nie był nigdzie zapisany ani sprawdzany.
4. *Dlaczego wdrożenie mimo to uznano za udane?* Pipeline robi tylko `kubectl apply`, a ta komenda kończy się sukcesem,
   gdy API Kubernetesa **przyjmie** manifest, nie gdy rollout się **zakończy**. Pipeline nie czekał na wynik
   (`kubectl rollout status`) i nie robił smoke testu wersji.
5. *Dlaczego nikt nie zauważył przez dobę?* Mechanizm bezpieczeństwa RollingUpdate zadziałał zgodnie z założeniem:
   nie zabił zdrowych podów v1, więc nie było awarii i żaden alert dostępności się nie odpalił. Jednocześnie nie było
   alertu na utknięty rollout (`ProgressDeadlineExceeded`) ani na rozjazd wersji. Awaria była **cicha**.

**Przyczyna w systemie:** proces wdrożenia mierzył sukces komendy (`apply`), a nie sukces wdrożenia
(nowa wersja działa i obsługuje ruch). Nic nie złapało niekompletnego artefaktu przed produkcją ani po niej.

**Co pomogło w diagnozie:**
- RollingUpdate z readiness probe: dzięki niemu błąd nie skończył się przestojem, a stara wersja dalej działała.
- Bardzo czytelne sygnały w klastrze: `0/1` przy nowym podzie, dwa ReplicaSety obok siebie, 404 w eventach
  i `not found` w logach Apache'a.
- Porównanie ConfigMap v1 i v2, które od razu pokazało brakujący plik.

**Co przeszkadzało w diagnozie:**
- Zielony pipeline dawał fałszywe poczucie, że wdrożenie jest OK, więc pierwszym podejrzanym mógł być cache, CDN
  albo klient, a nie sam rollout.
- Zgłoszenie przyszło od biznesu po dobie, a nie od monitoringu po kilku minutach.
- Pierwszy event (`connection refused`) jest mylący, bo to normalny stan przy starcie Apache'a. Właściwy sygnał to
  powtarzający się kod 404.

**Działania naprawcze:**
| # | Działanie | Typ | Cel |
|---|---|---|---|
| 1 | Dodać `health.php` do ConfigMapy `api-v2` (`_scenariusze/04b-api-v2.yaml`), wdrożyć i potwierdzić `"version":"v2"`. | poprawka | usunięcie objawu |
| 2 | W pipeline po `apply` dodać `kubectl rollout status deploy/api --timeout=5m`: utknięty rollout = czerwony build. | proces/CI | wdrożenie jest „zielone” dopiero, gdy faktycznie działa |
| 3 | Smoke test po wdrożeniu: `GET /` musi zwrócić oczekiwaną wersję (np. `"version":"v2"`). | test | wykrycie rozjazdu wersji |
| 4 | Alert na `kube_deployment_status_condition{condition="Progressing",status="false"}` (ProgressDeadlineExceeded) i na Deployment z więcej niż jednym aktywnym ReplicaSetem dłużej niż 15 min. | monitoring | cicha awaria wykryta w minutach, nie po dobie |
| 5 | Endpoint health jako część kodu aplikacji (ten sam artefakt co `index.php`), a nie osobny plik do pamiętania. | architektura | nie da się „zgubić” health checka |
| 6 | Test w CI: kontener z nowym artefaktem uruchomiony lokalnie musi odpowiadać 200 na ścieżce z `readinessProbe`. | test | niekompletny artefakt odpada przed produkcją |
| 7 | Rozważyć `kubectl rollout undo` / automatyczny rollback po przekroczeniu deadline'u (np. Argo Rollouts). | proces | jasny stan po nieudanym wdrożeniu zamiast „pół na pół” |

# Lekcja 03: Zasoby, skalowanie i rollouty

**Cel:** rozumieć, skąd się bierze `Pending`, jak działa autoskalowanie (HPA) i co dokładnie dzieje
się z podami podczas deployu. W pracy będzie to: „przeskaluj”, „dlaczego pod nie wstaje” i „dlaczego
deploy spowolnił produkcję”.

---

## Część A: metrics-server i `kubectl top`

Kubernetes sam z siebie **nie zbiera** zużycia CPU/RAM. Robi to dodatek **metrics-server**.
Bez niego nie działa `kubectl top` ani HPA. Na EKS trzeba go zainstalować (często jest już w IaC).

```powershell
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
# --kubelet-insecure-tls: TYLKO lokalnie (Docker Desktop ma certyfikaty self-signed)
helm install metrics-server metrics-server/metrics-server -n kube-system --set "args={--kubelet-insecure-tls}" --wait

# po ok. minucie:
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

### Requests vs. limits vs. faktyczne zużycie
```powershell
kubectl describe node | Select-String -Context 0,8 "Allocated resources"
```
Zobaczysz dwie różne rzeczy:
- **`kubectl top`** = ile pody **faktycznie zużywają** teraz,
- **`Allocated resources`** = ile pody **zarezerwowały** (suma `requests`).

**Scheduler patrzy tylko na requests**, a nie na faktyczne zużycie. Pod z `requests.cpu: 2`, który
zużywa 10m, i tak blokuje 2 rdzenie na nodzie.

| | Co robi | Gdy przekroczysz |
|---|---|---|
| `requests` | **rezerwacja**, decyduje, na którym nodzie wyląduje pod | nic, można zużywać więcej, jeśli node ma wolne |
| `limits.memory` | twardy sufit RAM | **OOMKilled** (lekcja 1) |
| `limits.cpu` | twardy sufit CPU | **throttling**: proces zwalnia, ale żyje (trudne do wykrycia!) |

**Zadanie A1:** porównaj `kubectl top pods -n staging` z `requests` w `values.yaml` (web: 50m CPU, 64Mi).
Ile procent rezerwacji faktycznie zużywa web? W AWS za rezerwacje płacisz (więcej requests = więcej
nodów EC2), dlatego „odchudzanie requests” to częste zadanie optymalizacyjne.

---

## Część B: `Pending`, czyli pod, który nie ma gdzie wylądować

```powershell
kubectl apply -f manifests/rollout.yaml     # tworzy też namespace lekcja3
kubectl apply -f manifests/pending.yaml
kubectl get pods -n lekcja3
```

**Zadanie B1:** pod `raport-roczny` jest w `Pending`. Znajdź przyczynę samym `kubectl` (wiesz już, gdzie szukać 😉).
Ile CPU ma Twój node? (`kubectl describe node`, sekcja `Capacity` / `Allocatable`)

**Zadanie B2:** napraw tak, żeby pod wstał. Potem zmień requests na `memory: 20Gi` (a CPU na rozsądne).
Jaki będzie komunikat tym razem?

> **W AWS (EKS):** `Pending` z `Insufficient cpu/memory` to często sygnał dla **Cluster Autoscalera / Karpentera**,
> żeby dołożyć nowy node EC2. Pod czeka wtedy 1–3 minuty i wstaje. Jeśli wisi dłużej, to albo osiągnięto
> limit nodów (w Terraformie: `max_size` node groupy), albo requests są większe niż największy typ instancji.
> Inne przyczyny `Pending`: PVC (dysk) w innej strefie AZ niż node, `nodeSelector`/`affinity`, którego żaden node nie spełnia.

---

## Część C: Rollout na żywo

Przy deployu Deployment tworzy **nowy ReplicaSet** i stopniowo przenosi repliki ze starego do nowego.
Tempo kontrolują dwie liczby:

```
replicas: 4, maxSurge: 25% (=1), maxUnavailable: 25% (=1)

  W trakcie rolloutu: max 4+1 = 5 podów łącznie, min 4-1 = 3 dostępne
  Zaokrąglanie: maxSurge w GÓRĘ, maxUnavailable w DÓŁ
```

Otwórz **drugi terminal** z obserwacją:
```powershell
kubectl get pods -n lekcja3 -l app=sklep -w
```

**C1. Udany rollout.** W pierwszym terminalu:
```powershell
kubectl set image deploy/sklep php=php:8.4-apache -n lekcja3
kubectl rollout status deploy/sklep -n lekcja3
```
Obserwuj, w jakiej kolejności pody powstają i znikają. Ile maksymalnie było naraz?

**C2. Zepsuty rollout przy domyślnej strategii.**
```powershell
kubectl set image deploy/sklep php=php:8.4-apahce -n lekcja3
kubectl get rs -n lekcja3       # ReplicaSety: ile podów ma stary, a ile nowy?
```
Ile **działających** podów zostało? Jak to się przekłada na pojemność aplikacji na produkcji?
Po ok. 2 min (`progressDeadlineSeconds: 120`): `kubectl rollout status deploy/sklep -n lekcja3`. Co mówi?
Sprzątnij: `kubectl rollout undo deploy/sklep -n lekcja3` (lokalnie wolno 😉)

**C3. Bezpieczna strategia.** W `rollout.yaml` ustaw `maxUnavailable: 0`, `apply`, i powtórz C2.
Ile działających podów zostało teraz? Jaki jest koszt tej strategii? (Hint: zasoby na nodach.)

**C4. „Wszystko naraz”.** Ustaw `maxSurge: 100%`, `maxUnavailable: 0` i zrób udany rollout (np. z powrotem
na `php:8.3-apache`). Co się dzieje i kiedy taka strategia ma sens?

> `type: Recreate` (zamiast RollingUpdate) najpierw zabija WSZYSTKIE stare pody, a dopiero potem tworzy nowe.
> Oznacza downtime, ale czasem jest konieczny, np. gdy dwie wersje aplikacji nie mogą działać jednocześnie
> (niekompatybilna migracja bazy).

---

## Część D: HPA, czyli autoskalowanie przez GitOps 🔥

Chart z lekcji 2 ma teraz `templates/hpa.yaml` i nowe pole w `values.yaml`:
```yaml
autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 60   # 60% z requests.cpu (50m), czyli ok. 30m na pod
```
Przeczytaj też, co się zmieniło w `templates/deployment.yaml` (`if not .Values.autoscaling.enabled`).

**D1. Włącz HPA na stagingu przez git.** W `02-helm-argo/chart/values-staging.yaml` dodaj:
```yaml
autoscaling:
  enabled: true
```
Commit, push, Refresh w Argo. Obserwuj `kubectl get pods -n staging -w` **w momencie synca**.
Czy liczba podów web przez chwilę spadła? Dlaczego? (Hint: co się dzieje, gdy z Deploymentu znika pole `replicas`?)

**D2. Obciąż aplikację.** `cpu.php` zjada ok. 200 ms CPU na request.
```powershell
# terminal 1: obserwacja
kubectl get hpa -n staging -w

# terminal 2: generator ruchu (pod, który w pętli odpytuje aplikację)
kubectl run obciazenie -n staging --image=busybox:1.37 --restart=Never -- sh -c "while true; do wget -q -O- http://demo-web/cpu.php >/dev/null; done"
```
Obserwuj kolumny `TARGETS` (cpu%) i `REPLICAS`. Do ilu replik doszło? Dlaczego nie więcej?
Sprawdź też `kubectl top pods -n staging`.

**D3. Zdejmij obciążenie.**
```powershell
kubectl delete pod obciazenie -n staging
```
Jak szybko HPA zmniejsza liczbę replik? (Domyślnie scale-down czeka **5 minut** stabilizacji, żeby nie
„pływać” góra-dół przy skokach ruchu. Scale-up jest prawie natychmiastowy.)

**D4. Argo a HPA.** HPA zmienia liczbę replik, a Argo ma self-heal. Czy Argo pokazuje `OutOfSync`? Dlaczego nie?

---

## Pytania kontrolne
1. Co pokaże HPA (kolumna TARGETS), jeśli Deployment **nie ma** `requests.cpu`? Dlaczego?
2. HPA doszedł do `maxReplicas` i CPU dalej jest 200%. Co się dzieje z aplikacją i co możesz zrobić?
3. HPA chce 6 replik, ale 2 nowe są w `Pending`. Co to znaczy i co w AWS powinno to naprawić?
4. Workery RabbitMQ: czy skalowanie po CPU to dobry pomysł? Po czym lepiej by je skalować?

---

## Sprzątanie
```powershell
kubectl delete namespace lekcja3
kubectl delete pod obciazenie -n staging --ignore-not-found
```
HPA na stagingu i metrics-server możesz zostawić.

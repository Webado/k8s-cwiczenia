# Lekcja 02: Helm + Argo CD (GitOps)

**Cel:** zrozumieć, jak w firmie zmiana trafia na klaster: **commit/PR -> git -> Argo CD -> Kubernetes**.
Umieć przeskalować aplikację „po bożemu”, zrobić rollback i odczytać stan w Argo.

```
 Ty                    GitHub                   Argo CD (w klastrze)            Kubernetes
 ───                   ──────                   ────────────────────            ──────────
 edytujesz values  ──► commit / PR / merge ──►  co ~3 min pobiera repo,    ──►  Deployment, Service...
 -staging.yaml                                  renderuje Helm chart,
                                                porównuje z klastrem:
                                                Synced / OutOfSync
```

---

## Część A: Helm (bez Argo)

Najpierw sam Helm, żeby było jasne, co Argo potem robi automatycznie.

### Struktura charta
```
chart/
├── Chart.yaml               metadane (nazwa, wersja)
├── values.yaml              wartości domyślne
├── values-staging.yaml      nadpisania dla stagingu
├── values-production.yaml   nadpisania dla produkcji
└── templates/               szablony YAML z {{ .Values.coś }}
    ├── _helpers.tpl         "funkcje" (wspólne labele)
    ├── configmap.yaml
    ├── deployment.yaml      porównaj z 01-k8s-podstawy/manifests/20-web.yaml!
    ├── service.yaml
    └── worker.yaml          tworzony tylko gdy worker.enabled = true
```

### Ćwiczenia (w folderze `02-helm-argo`)

```powershell
# 1. Zobacz, co Helm WYGENERUJE (nic nie instaluje, tylko renderuje)
#    NAJWAŻNIEJSZA komenda przy czytaniu cudzych chartów
helm template demo ./chart
helm template demo ./chart -f chart/values-staging.yaml
helm template demo ./chart -f chart/values-production.yaml
```
**Zadanie A1:** porównaj trzy wyniki powyżej. Co się różni? Dlaczego w pierwszym nie ma workera?

```powershell
# 2. Instalacja (release = zainstalowana instancja charta)
helm install demo ./chart -f chart/values-staging.yaml -n helm-test --create-namespace
helm list -n helm-test
kubectl get pods -n helm-test

# 3. Upgrade: zmiana wartości bez edycji plików (--set nadpisuje values)
helm upgrade demo ./chart -f chart/values-staging.yaml --set replicaCount=4 -n helm-test
helm upgrade demo ./chart -f chart/values-staging.yaml --set appVersion=2.0.0 -n helm-test
kubectl exec -n helm-test deploy/demo-web -- curl -s http://demo-web/

# 4. Historia i rollback CAŁEJ aplikacji naraz
helm history demo -n helm-test
helm rollback demo 1 -n helm-test

# 5. Co dokładnie jest teraz zainstalowane?
helm get values demo -n helm-test      # z jakimi wartościami
helm get manifest demo -n helm-test    # pełny wyrenderowany YAML

# 6. Sprzątanie
helm uninstall demo -n helm-test
kubectl delete namespace helm-test
```

**Zadanie A2:** po `--set appVersion=2.0.0` pody zrestartowały się **same**, choć zmieniła się tylko
ConfigMapa. W lekcji 1 trzeba było robić `rollout restart`. Znajdź w `templates/deployment.yaml`, co to załatwia.

**Zadanie A3:** w `values.yaml` worker jest wyłączony. Znajdź w `templates/worker.yaml`, jak to działa.
Przy okazji: worker ma `trap ... TERM`. Usuń poda workera i zmierz, ile trwa `Terminating`.
Porównaj z `mailer` z lekcji 1.

> ⚠️ W pracy, jeśli aplikacje są zarządzane przez Argo, **nie rób `helm upgrade` ręcznie**.
> Argo uzna to za ręczną zmianę i cofnie. `helm template` / `helm get` (czytanie) są zawsze OK.

---

## Część B: Argo CD

### B1. Instalacja Argo CD (przez Helma, bo tak instaluje się gotowe narzędzia)
```powershell
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace -f argocd/argocd-values.yaml --wait

kubectl get pods -n argocd     # kilka komponentów: server, repo-server, application-controller...
```

### B2. Logowanie do UI
```powershell
# hasło admina (Secret jest w base64, więc dekodujemy)
$b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))

kubectl port-forward svc/argocd-server -n argocd 8080:80
```
Otwórz **http://localhost:8080**, login: `admin`, hasło: to z komendy wyżej.

### B3. Podłącz aplikacje
```powershell
kubectl apply -f argocd/demo-staging.yaml
kubectl apply -f argocd/demo-production.yaml
```
Przeczytaj oba pliki: **staging ma `automated` (auto-sync + self-heal), produkcja nie.**

W UI zobaczysz:
- **demo-staging**: po chwili `Synced` + `Healthy`. Argo sam wdrożył.
- **demo-production**: `OutOfSync`. Argo wie, co powinno być, ale czeka na człowieka. Kliknij
  w aplikację, obejrzyj **APP DIFF**, potem **SYNC**.

Kliknij w aplikację i obejrzyj drzewko: Application -> Deployment -> ReplicaSet -> Pod. To jest to samo,
co `kubectl get`, tylko w obrazkach. Tu będziesz zaglądał w pracy „sprawdzić, co się dzieje”.

### Słowniczek statusów Argo
| Status | Znaczenie |
|---|---|
| **Synced** | klaster = git |
| **OutOfSync** | klaster ≠ git (ktoś zmienił git i nie zsynchronizowano, albo ktoś zmienił klaster ręcznie) |
| **Healthy** | zasoby działają (pody Ready itd.) |
| **Progressing** | trwa rollout |
| **Degraded** | coś nie działa (np. pod w CrashLoopBackOff) |
| **Missing** | zasób jest w gicie, a nie ma go w klastrze |

---

## Część C: Zadania GitOps 🔥

### C1. Skalowanie „po bożemu”
1. W `chart/values-staging.yaml` zmień `replicaCount: 2` na `3`.
2. `git add`, `git commit -m "Scale staging web to 3"`, `git push`.
3. W Argo kliknij **REFRESH** (domyślnie Argo sprawdza gita co ~3 minuty) i obserwuj.

### C2. Ręczna zmiana vs self-heal
```powershell
kubectl scale deploy/demo-web -n staging --replicas=6
kubectl get pods -n staging -w
```
Co się stało? A teraz to samo na produkcji (`-n production`). Dlaczego zachowanie jest inne?
Co pokazuje Argo przy `demo-production`?

### C3. Zmiana przez Pull Request (tak będzie w pracy)
```powershell
git switch -c zmiana-wiadomosci
# edytuj message w chart/values-staging.yaml
git commit -am "Change staging message"
git push -u origin zmiana-wiadomosci
gh pr create --fill
gh pr merge --squash --delete-branch
git switch main; git pull
```
Argo obserwuje gałąź `main`, więc zmiana wchodzi dopiero po merge'u. Na tym polega code review dla infrastruktury.

### C4. Zepsuty deploy i rollback
1. W `values-staging.yaml` dodaj:
   ```yaml
   image:
     tag: "8.3-apahce"
   ```
   Commit + push + Refresh.
2. Obserwuj Argo i `kubectl get pods -n staging`. **Czy strona przestała działać?** Dlaczego nie?
   *(Hint: rolling update. Nowy pod nie wstaje, więc stare nie są wyłączane.)*
3. Napraw przez git, a nie przez kubectl:
   ```powershell
   git revert HEAD --no-edit
   git push
   ```

### C5. Pytania kontrolne
1. Kolega mówi: „przeskalowałem prod kubectl-em, bo był pożar”. Co musi zrobić zaraz potem i dlaczego?
2. Usunąłeś plik `templates/worker.yaml` z repo. Co się stanie na stagingu, a co na produkcji? (Hint: `prune`)
3. Gdzie zajrzysz najpierw, gdy po merge'u PR-a „nic się nie zmieniło na stagingu”?

---

## Sprzątanie (gdy skończysz całą lekcję)
```powershell
kubectl delete -f argocd/demo-staging.yaml -f argocd/demo-production.yaml
kubectl delete namespace staging production
helm uninstall argocd -n argocd
kubectl delete namespace argocd
```
Albo zostaw Argo, przyda się w kolejnych lekcjach.

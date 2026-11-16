# Lekcja 01: Kubernetes przez debugowanie

**Cel:** po tej lekcji otwierasz dowolny YAML z Kubernetesa i wiesz, co czytasz. Jak coś nie
wstaje, wiesz, którymi komendami do tego dojść.

---

## 1. Model mentalny w 2 minuty

Kubernetes to **pętla uzgadniania stanu**. Ty deklarujesz w YAML-u *jak ma być* („chcę 2 pody
z obrazem X”). Kubernetes w kółko porównuje *jak jest* z *jak ma być* i to naprawia.
Zabijesz poda? Za sekundę powstanie nowy. Dlatego manifesty to **deklaracje, a nie skrypty**.

(Argo CD robi dokładnie to samo, tylko o poziom wyżej: porównuje *klaster* z *gitem*.)

```
Cluster
 └─ Node (maszyna, np. EC2 w AWS)            kubectl get nodes
     └─ Pod (1+ kontenerów, wspólne IP)       kubectl get pods
         └─ Container (Twój obraz Dockera)

Namespace   – "folder" na zasoby               kubectl get ns
Deployment  – "chcę N replik tego poda"        kubectl get deploy
 └─ ReplicaSet – konkretna wersja Deploymentu (nowy obraz = nowy ReplicaSet)
Service     – stały DNS/IP przed grupą podów   kubectl get svc
Ingress     – HTTP z internetu -> Service      kubectl get ingress
ConfigMap / Secret – konfiguracja / hasła
```

**Labele i selektory to klej całego systemu.** Deployment znajduje swoje pody po labelu.
Service znajduje pody po labelu. Literówka w labelu = rzeczy „nie widzą się” i nie ma
żadnego błędu, po prostu nic nie działa. (Zobaczysz w awarii nr 3.)

### Inne obiekty, które spotkasz w pracy
| Obiekt | Po co | Przykład u nich |
|---|---|---|
| **StatefulSet** | pody ze stałą nazwą i własnym dyskiem | RabbitMQ, Elasticsearch |
| **Job / CronJob** | jednorazowe / cykliczne zadania | migracje Doctrine, raporty nocne |
| **HPA** | autoskalowanie replik po CPU/metrykach | workery pod obciążeniem |
| **PersistentVolumeClaim** | „daj mi dysk” (w AWS -> EBS) | dane kolejek |
| **ServiceAccount** | tożsamość poda (w AWS mapowana na rolę IAM) | dostęp do S3 |

---

## 2. Uruchom

```powershell
kubectl apply -f manifests/          # apply = "doprowadź klaster do stanu z tych plików"
kubectl get all -n lekcja1           # co powstało
kubectl get pods -n lekcja1 -w       # -w = obserwuj na żywo (Ctrl+C, żeby wyjść)
```

Przeczytaj pliki w `manifests/` po kolei (00 -> 30). Komentarze tłumaczą każdy ważny fragment.

---

## 3. Komendy, które naprawdę będziesz używał

```powershell
# --- Ogląd ---
kubectl get pods -n lekcja1 -o wide          # + na którym nodzie, jakie IP
kubectl get pods -A                          # wszystkie namespace'y
kubectl describe pod <nazwa> -n lekcja1      # NAJWAŻNIEJSZA: sekcja "Events" na dole!
kubectl get events -n lekcja1 --sort-by=.lastTimestamp

# --- Logi ---
kubectl logs <pod> -n lekcja1                # logi kontenera
kubectl logs <pod> -n lekcja1 --previous     # logi POPRZEDNIEGO kontenera (po crashu!)
kubectl logs deploy/web -n lekcja1 -f        # -f = follow, jak tail -f

# --- Wejście do środka ---
kubectl exec -it deploy/web -n lekcja1 -- bash
kubectl exec deploy/web -n lekcja1 -- env    # jakie zmienne środowiskowe widzi apka

# --- Dostęp z Twojego kompa ---
kubectl port-forward svc/web 8080:80 -n lekcja1             # -> http://localhost:8080
kubectl port-forward svc/rabbitmq 15672:15672 -n lekcja1    # -> panel RabbitMQ (app / super-tajne-haslo)

# --- Zmiany (na produkcji z Argo: ostrożnie, patrz niżej!) ---
kubectl scale deploy/web --replicas=4 -n lekcja1
kubectl rollout restart deploy/web -n lekcja1   # restart wszystkich podów po kolei, bez downtime'u
kubectl rollout history deploy/web -n lekcja1
kubectl rollout undo deploy/web -n lekcja1      # rollback do poprzedniej wersji
```

> Tip: żeby nie pisać ciągle `-n lekcja1`:
> `kubectl config set-context --current --namespace=lekcja1`

### Ściąga: STATUS poda -> co sprawdzić
| Status | Znaczenie | Gdzie szukać |
|---|---|---|
| `Pending` | scheduler nie może nigdzie wcisnąć poda | `describe` -> Events (za mało CPU/RAM? brak dysku?) |
| `ImagePullBackOff` / `ErrImagePull` | nie da się pobrać obrazu | `describe` -> zła nazwa/tag? brak dostępu do rejestru (ECR)? |
| `CreateContainerConfigError` | brakuje ConfigMapy/Secreta albo klucza | `describe` -> Events |
| `CrashLoopBackOff` | kontener startuje i umiera | `logs --previous`, `describe` -> Last State / Exit Code |
| `OOMKilled` (exit code 137) | przekroczył **limit pamięci** | `describe` -> Last State; podnieść limit albo naprawić wyciek |
| `Running`, ale `0/1` READY | readinessProbe nie przechodzi, pod nie dostaje ruchu | `describe` -> Events: „Readiness probe failed” |
| `Running 1/1`, a i tak nie działa | problem z Service/Ingress/siecią | `kubectl get endpointslices`, labele, porty |

---

## 4. Zadania

1. Otwórz `http://localhost:8080` przez port-forward. Odśwież kilka razy. Czy nazwa poda się zmienia?
   *(Hint: port-forward na `svc/` i tak przypina się do jednego poda. Spróbuj
   `kubectl exec deploy/web -n lekcja1 -- curl -s http://web/` kilka razy.)*
2. Usuń jednego poda `web` (`kubectl delete pod ...`) i obserwuj `get pods -w`. Co się dzieje i dlaczego?
3. Zmień w `10-config.yaml` `APP_ENV` na `staging`, zrób `apply`. Czy strona pokazuje nową wartość?
   Dlaczego nie? Co trzeba zrobić? *(To częsty gotcha na produkcji!)*
4. Przeskaluj `web` do 4 replik. Potem zrób `kubectl apply -f manifests/` jeszcze raz. Ile jest replik?
   Tak samo zachowa się Argo CD z self-heal: **plik wygrywa z ręczną zmianą.**
5. Zaloguj się do panelu RabbitMQ przez port-forward. Znajdź połączenia/kolejki.
6. Znajdź w manifestach 3 rzeczy, które są OK lokalnie, ale byłyby problemem na produkcji.
   *(To jest dokładnie to „szukanie problemów w IaC” z rozmowy.)*

---

## 5. Awarie 🔥

```powershell
kubectl apply -f awarie/awarie.yaml
kubectl get pods -n awarie
```

Jest **5 zepsutych aplikacji**: `sklep`, `raporty`, `api`, `mailer`, `panel`.
Zasada: **nie czytaj `awarie.yaml`**. Diagnozuj tylko przez `kubectl` (tak jak na produkcji, gdzie
najpierw widzisz objaw, a dopiero potem szukasz pliku). Dla każdej zapisz:
- **objaw** (co widać),
- **przyczynę** (komenda, która to pokazała),
- **poprawkę**. Napraw w YAML-u i zrób `apply`.

Uwaga: dwie awarie wyglądają na pierwszy rzut oka jak „wszystko Running”. 😉

Rozwiązania: `awarie/ROZWIAZANIA.md` (dopiero po próbie!). Albo napisz do Claude'a „sprawdź moje
diagnozy” i wklej swoje notatki.

---

## 6. Sprzątanie

```powershell
kubectl delete namespace lekcja1 awarie    # usuwa namespace razem z całą zawartością
```

---

## ⚠️ Zanim dotkniesz klastra w pracy

- Zawsze sprawdź **kontekst**: `kubectl config current-context`. Pomylenie stagingu z prodem to klasyk.
- Jeśli klaster jest zarządzany przez **Argo CD**, ręczne `kubectl scale/edit/apply` zostanie
  cofnięte (self-heal) albo zrobi „OutOfSync”. Zmiany robi się w repo (PR), a Argo synchronizuje.
  Wyjątek: awaryjny hotfix. Wtedy *zawsze* potem przenieś zmianę do gita.
- `kubectl rollout undo` to rollback „obok” plików. Kolejny `apply` może zachować się dziwnie
  (warning o `last-applied-configuration`). Docelowy rollback = `git revert` + apply/sync.
  `undo` używaj jako szybkiego gaszenia pożaru, a potem wyrównaj repo.
- Komendy tylko do odczytu (`get`, `describe`, `logs`) są bezpieczne. Od nich zacznij.

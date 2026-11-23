# Rozwiązania incydentów (spoilery!)

## #1 Maile nie wychodzą: zła nazwa hosta RabbitMQ
- **Objaw:** `mailer` w `CrashLoopBackOff`.
- **Dowód:** `kubectl logs deploy/mailer -n incydenty --previous`:
  `Unable to connect to tcp://rabbitmq-svc:5672 (getaddrinfo for rabbitmq-svc failed)`.
  Do tego `kubectl get svc -n incydenty`: Service nazywa się `rabbitmq`, a nie `rabbitmq-svc`.
- **Przyczyna:** w ConfigMapie `mailer-config` jest `RABBITMQ_HOST: "rabbitmq-svc"`.
- **Poprawka:** `RABBITMQ_HOST: "rabbitmq"`, `apply`, a potem **`kubectl rollout restart deploy/mailer -n incydenty`**.
  Niuans (sprawdzony na Twoim klastrze): kontener w CrashLoopBackOff **sam** złapie nową wartość przy kolejnym
  restarcie, bo kubelet odczytuje env z ConfigMapy przy każdym starcie kontenera. Ale backoff może trwać
  do 5 minut, więc `rollout restart` naprawia od razu. A działający, zdrowy pod (lekcja 1, zadanie 3)
  nowej wartości **nie dostanie nigdy**, dopóki się nie zrestartuje.
- **Jak zapobiec:** alert na CrashLoopBackOff i na długość kolejki `emails.*`. Nazwy Service'ów generowane w Helm
  (`{{ .Release.Name }}-rabbitmq`) zamiast wpisywanych ręcznie.
- **Na produkcji:** kolejka w RabbitMQ rośnie. Po naprawie worker nadrobi zaległości, a klienci dostaną maile z opóźnieniem.
  Warto to zakomunikować supportowi.

## #2 Raport miesięczny: CronJob zabijany przez OOM
- **Objaw:** `kubectl get cronjob,job -n incydenty`: kolejne joby w stanie `Failed`, `COMPLETIONS 0/1`.
- **Dowód:** `kubectl get pods -n incydenty`: pody `raport-miesieczny-...` w `OOMKilled`.
  `kubectl describe pod ...`: `Reason: OOMKilled, Exit Code: 137`. W logach tylko „Generuję raport...”, a potem nic.
- **Przyczyna:** generator ładuje ok. 250 MB danych do pamięci, a `limits.memory: 128Mi`.
- **Poprawka doraźna:** limit np. `512Mi` w CronJobie. Zmiana dotyczy **następnego** uruchomienia. Żeby nie czekać:
  `kubectl create job --from=cronjob/raport-miesieczny raport-reczny -n incydenty`.
- **Poprawka trwała:** generowanie strumieniowe / w paczkach, a nie wszystko naraz w pamięci.
- **Jak zapobiec:** alert na nieudane Joby (`kube_job_status_failed`). CronJob, który pada raz w miesiącu,
  bez alertu potrafi nie działać miesiącami („w zeszłym miesiącu też były problemy”).

## #3 Panel muli: CPU throttling
- **Objaw:** strona ładuje się kilka sekund. Zero błędów, zero restartów.
- **Dowód:** `kubectl top pod -n incydenty -l app=panel`: ok. 17–20m CPU. `kubectl describe pod`: `limits: cpu: 20m`.
  Zużycie przyklejone do limitu = throttling. Strona sama pisze „wygenerowana w ~3000 ms”, a bez limitu to ok. 31 ms.
- **Przyczyna:** limit CPU 20m (2% rdzenia). Kernel daje procesowi 2 ms CPU na każde 100 ms, a resztę czasu proces czeka.
- **Poprawka:** podnieść albo usunąć `limits.cpu` (zostawić sensowne `requests.cpu`).
  Wiele zespołów świadomie **nie ustawia limitów CPU** właśnie przez throttling (lekcja 1, zadanie 6).
- **Jak zapobiec:** metryka `container_cpu_cfs_throttled_periods_total` w monitoringu. Review zmian w `resources`.

## #4 API v2 nie widać: rollout utknął
- **Objaw:** `wget http://api/` zwraca `"version":"v1"`.
- **Dowód:** `kubectl get rs -n incydenty -l app=api`: stary ReplicaSet 3/3, nowy 1 pod `0/1`.
  `kubectl rollout status deploy/api -n incydenty` wisi. `describe` nowego poda:
  `Readiness probe failed: HTTP probe failed with statuscode: 404`.
- **Przyczyna:** ConfigMapa `api-v2` nie zawiera `health.php`, a readinessProbe sprawdza `/health.php`.
  Rolling update (maxUnavailable = 0 przy 3 replikach) chroni klientów przed zepsutą wersją, więc nadal obsługuje ich v1.
- **Poprawka:** dodać `health.php` do `api-v2`. Pliki z ConfigMapy montowanej jako **volume** aktualizują się same
  (ok. 1 min), więc readiness zacznie przechodzić i rollout ruszy **bez restartu**.
- **Obserwacja bonusowa:** jeśli w trakcie rolloutu odpytujesz `api` w pętli, kilka requestów może dostać
  `Connection refused`. Stary pod zamyka się, zanim K8s zdąży go usunąć z endpointów Service'u.
  To ten efekt, który rozwiązuje `lifecycle.preStop: sleep 5` (rozmowa o SIGWINCH po lekcji 5).
- **Jak zapobiec:** „Pipeline był zielony!”, bo pipeline sprawdza, czy `apply` się udał, a nie czy rollout się
  zakończył. Do pipeline'u: `kubectl rollout status --timeout=...` (albo w Argo: health = Progressing, alert po X min).

## #5 Sklep: 3 z 6 replik, ResourceQuota
- **Objaw:** `kubectl get deploy -n incydenty-sklep`: `3/6`. Brak Pending, brak restartów.
- **Dowód:** `kubectl get events -n incydenty-sklep`:
  `Error creating: pods "sklep-..." is forbidden: exceeded quota: limity-zespolu, requested: requests.memory=128Mi, used: requests.memory=384Mi, limited: requests.memory=400Mi`.
- **Przyczyna:** ResourceQuota namespace'u pozwala na 400Mi requestów pamięci, a 6 × 128Mi = 768Mi.
- **Poprawka:** podnieść quotę (to decyzja: kto ją ustawił i dlaczego? quota to często budżet zespołu)
  **albo** zmniejszyć requests, jeśli są przewymiarowane (`kubectl top` pokaże faktyczne zużycie, ok. 10 MB!).
  Tu najlepsza odpowiedź to prawdopodobnie obie rzeczy naraz: requests 32–64Mi i quota z zapasem na szczyt.
- **Jak zapobiec:** alert „Deployment ma mniej dostępnych replik niż żądanych przez X minut”
  (`kube_deployment_status_replicas_available < kube_deployment_spec_replicas`).

## B4: Argo sync failed
Po dodaniu `requests.memory: 64Mi` > `limits.memory: 32Mi` API Kubernetesa **odrzuca** Deployment.
Argo pokazuje **Sync failed / OutOfSync**, a w szczegółach `must be less than or equal to memory limit`.
Działające pody dalej mają starą wersję (nic nie zostało zastosowane), więc staging nadal działa.
Poprawka: usunąć błędne `resources` z `values-staging.yaml` albo ustawić `requests ≤ limits`.

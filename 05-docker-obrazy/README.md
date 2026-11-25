# Lekcja 05: Odchudzanie obrazów Dockera

**Cel:** wziąć ciężki, wolno budujący się obraz PHP i krok po kroku zrobić z niego szybki, mały i bezpieczny.
Na rozmowie padło: *„odchudzać duże dockery, przez które środowiska lokalne są ociężałe i długo się budują”*.

## Dlaczego to ważne (nie tylko lokalnie)

| Problem z dużym obrazem | Skutek |
|---|---|
| Wolny build | każdy PR w CI czeka minutami, a developer lokalnie też |
| Duży rozmiar | nowy node w EKS (autoskalowanie z lekcji 3!) **ściąga obraz dłużej**, więc pod startuje później w szczycie ruchu |
| Zbędne narzędzia (vim, git, curl, kompilatory) | więcej **CVE** w skanerach bezpieczeństwa i więcej narzędzi dla atakującego |
| xdebug / paczki dev na produkcji | wolniejsze PHP, `var-dumper`/`phpunit` dostępne na produkcji |
| Zły PID 1 | wolne i brutalne zamykanie podów przy każdym deployu (lekcja 2) |

---

## Jak działa cache warstw: jedyna teoria, której potrzebujesz

```
FROM php:8.3-apache         ─► warstwa 1   ┐
RUN apt-get install ...     ─► warstwa 2   │ Docker sprawdza każdą instrukcję po kolei:
COPY . .                    ─► warstwa 3   │ "czy wejście się zmieniło?"
RUN composer install        ─► warstwa 4   ┘ NIE  -> bierze warstwę z cache (0 s)
                                             TAK  -> buduje ją od nowa ORAZ WSZYSTKIE PONIŻEJ
```
Dwie zasady wynikają z tego wprost:
1. **To, co zmienia się rzadko, na górę. To, co często (kod), na dół.**
2. **Warstwy są niezmienne.** Plik dodany w warstwie 2 i usunięty w warstwie 5 **dalej zajmuje miejsce** w obrazie
   (warstwa 5 tylko go „zasłania”). Sprzątać trzeba w **tej samej** instrukcji `RUN`, w której się nabałaganiło.

---

## Krok 0: przygotowanie

W `app/` jest mała aplikacja PHP (strona `public/index.php` + worker kolejki `bin/worker.php`) i **zły** `Dockerfile`.
Przeczytaj go teraz. Ile grzechów widzisz od razu?

Zasymuluj śmieci, które w prawdziwych projektach leżą w katalogu (dump bazy, logi, cache):
```powershell
cd 05-docker-obrazy/app
New-Item -ItemType Directory -Force var | Out-Null
$f = [IO.File]::Create("$PWD\var\dump.sql"); $f.SetLength(300MB); $f.Close()
```

## Krok 1: pomiar „przed”

```powershell
Measure-Command { docker build -t sklep:bad . | Out-Default }
docker images sklep
docker history sklep:bad          # rozmiar KAŻDEJ warstwy
```
Zapisz: **czas builda** i **rozmiar obrazu**. Popatrz też na początek logu builda: `transferring context: ...`.
Ile MB wysłałeś do Dockera, zanim cokolwiek się zbudowało?

Uruchom i zobacz, co jest w środku:
```powershell
docker run -d --rm --name sklep -p 8081:80 sklep:bad
curl.exe -s http://localhost:8081
docker exec sklep ls -la var/                 # czy dump bazy trafił do obrazu?
docker exec sklep sh -c "which vim git curl"  # narzędzia na produkcji?
docker stop sklep
```

## Krok 2: test cache

Zmień jedną literkę w `public/index.php` (np. „Sklep działa!” na „Sklep działa!!”) i zbuduj jeszcze raz:
```powershell
Measure-Command { docker build -t sklep:bad . | Out-Default }
```
Które kroki się przebudowały? Dlaczego `composer install` leci od nowa, skoro nie zmieniłeś żadnej zależności?
**To jest ten „długo się buduje” z rozmowy:** każda zmiana w kodzie = pełny `composer install`.

---

## Kroki 3–8: naprawa

Edytuj `app/Dockerfile` (i inne pliki w `app/`). Po każdym kroku buduj i porównuj czas i rozmiar.
Wzorcowe rozwiązanie jest w `rozwiazanie/`, ale zajrzyj tam dopiero po swojej próbie.

### Krok 3: `app/.dockerignore`
Stwórz `app/.dockerignore`, który wyklucza z builda wszystko, co nie powinno trafić do obrazu.
Co powinno się tam znaleźć? (Pomyśl: śmieci, testy, lokalny `vendor/`, pliki Dockera, git.)
Sprawdź `transferring context` jeszcze raz.

> Pułapka z życia: bez `vendor/` w `app/.dockerignore` lokalny `vendor/` (z paczkami dev, zbudowany na innej wersji PHP)
> jest kopiowany do obrazu przez `COPY . .` i nadpisuje to, co zainstalował composer.

### Krok 4: kolejność warstw
Spraw, żeby `composer install` wykonywał się **tylko wtedy, gdy zmienią się `composer.json` / `composer.lock`**.
*(Hint: dwa `COPY`. Najpierw tylko pliki composera, potem `composer install`, potem reszta kodu.)*
Powtórz test z kroku 2. Ile trwa teraz build po zmianie w kodzie?

> `composer install` przed skopiowaniem kodu nie zbuduje autoloadera klas aplikacji, więc użyj
> `--no-autoloader --no-scripts`, a po `COPY . .` zrób `composer dump-autoload`.

### Krok 5: apt i sprzątanie
- Czy `apt-get clean && rm -rf /var/lib/apt/lists/*` w **osobnym** `RUN` coś daje? Sprawdź w `docker history`.
- Czy `vim`, `wget`, `git` są potrzebne do działania aplikacji?
- Biblioteki `*-dev` (`libicu-dev`, `libzip-dev`...) są potrzebne tylko **do kompilacji** rozszerzeń PHP.

Najprostsza droga w świecie PHP: narzędzie **`install-php-extensions`**, które instaluje rozszerzenia, a potem samo
usuwa wszystko, co było potrzebne tylko do kompilacji:
```dockerfile
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions intl zip gd pcntl
```
Zobaczysz je w wielu firmowych Dockerfile'ach.

### Krok 6: multi-stage build
Composer jest potrzebny do **zbudowania** `vendor/`, ale nie do **działania** aplikacji. Tak samo jego cache.
```dockerfile
FROM php:8.3-apache AS base      # wspólna podstawa
...
FROM base AS vendor              # etap pomocniczy: composer, install
...
FROM base AS prod                # obraz końcowy
COPY --from=vendor /var/www/html /var/www/html   # bierzemy TYLKO wynik
```
Do obrazu końcowego trafia **tylko ostatni etap**. Wszystko z etapów pośrednich (composer, cache) zostaje za burtą.
Przy okazji: `composer install --no-dev`, bo phpunit i phpstan nie są potrzebne na produkcji.

### Krok 7: targety dev i prod
Jeden Dockerfile, dwa warianty:
- **`dev`**: xdebug, composer, kod **montowany z dysku** (volume), więc zmiany są widoczne bez rebuilda.
- **`prod`**: bez xdebuga, `php.ini-production`, **opcache** z `validate_timestamps=0` (PHP nie sprawdza na każdym
  requeście, czy pliki się zmieniły, bo na produkcji się nie zmieniają).

```powershell
docker build --target dev  -t sklep:dev  .
docker build --target prod -t sklep:prod .
```
Zobacz też `rozwiazanie/compose.yaml`: tak wygląda lokalne środowisko na targecie `dev`.

> **„Ociężałe środowisko lokalne” w praktyce** to zwykle jedno z trzech:
> 1. rebuild obrazu przy każdej zmianie kodu, zamiast volume z kodem,
> 2. wolne volume'y na Windows/Mac (kod na dysku Windows, montowany do Linuxa). Pomaga trzymanie projektu w WSL2
>    albo trzymanie `vendor/` w osobnym volume,
> 3. obraz dev = obraz prod z dorzuconym wszystkim, czyli gigant.

### Krok 8: PID 1 i SIGTERM (powrót do lekcji 2)
```powershell
docker run -d --name worker-test sklep:bad worker
docker logs worker-test
Measure-Command { docker stop worker-test | Out-Default }    # ile trwało?
docker logs worker-test                                     # czy worker wypisał "SIGTERM: kończę..."?
docker inspect worker-test --format '{{.State.ExitCode}}'   # exit code
docker rm worker-test
```
`worker.php` **ma** handler SIGTERM (`pcntl_signal`), a mimo to nie zadziałał. Co oznacza exit code 137? (Lekcja 1!)

**Tu są DWIE przyczyny naraz.** Śledztwo:
```powershell
docker run -d --name worker-test sklep:bad worker
docker exec worker-test cat /proc/1/cmdline                      # 1) kto jest PID 1?
docker image inspect sklep:bad --format '{{.Config.StopSignal}}' # 2) JAKI sygnał wysyła docker stop?
docker rm -f worker-test
```
1. **PID 1:** napraw w `docker-entrypoint.sh` *(Hint: jedno słowo przed `php` i przed `apache2-foreground`)*.
2. **Sygnał:** skąd się wziął, skoro go nie ustawiałeś? *(Hint: `FROM`.)* Dlaczego dla Apache'a jest OK, a dla workera nie?
   Jak dać workerowi inny sygnał, nie psując Apache'a? *(Hint: osobny target `worker` w Dockerfile.)*

Po naprawie `docker stop` workera powinien trwać poniżej sekundy, z exit code `0` i logiem `Worker zakończony czysto`.

> **Dlaczego to ważne na K8s:** containerd (runtime Kubernetesa) też respektuje `STOPSIGNAL` z obrazu.
> Worker RabbitMQ zbudowany na obrazie `php:apache` przy **każdym deployu** byłby zabijany w trakcie przetwarzania
> wiadomości, mimo że w kodzie jest poprawna obsługa SIGTERM. Code review PHP-a by tego nie wyłapało.

---

## Krok 9: wynik

Wypełnij tabelkę i wklej ją Claude'owi:

| | `sklep:bad` | Twój `sklep:prod` |
|---|---|---|
| Rozmiar obrazu | | |
| Pierwszy build | | |
| Build po zmianie 1 linii kodu | | |
| `transferring context` | | |
| xdebug na produkcji? | | |
| paczki dev (phpunit)? | | |
| `docker stop` workera (czas + exit code) | | |

Sprawdź też stronę z obrazu prod (`docker run -d --rm -p 8082:80 sklep:prod`, potem `curl.exe -s http://localhost:8082`).
Powinna pokazać: xdebug **nie**, opcache **TAK**, paczki dev **nie**.

---

## Bonusy (jeśli chcesz pójść dalej)
- **Non-root:** obraz prod dalej startuje jako root (Apache potrzebuje roota do portu 80). Jak to zmienić?
  (Hint: Apache na porcie 8080 + `USER www-data`.) W K8s wymusza się to przez `securityContext.runAsNonRoot`.
- **Alpine:** `php:8.3-fpm-alpine` + nginx potrafi dać obraz kilkukrotnie mniejszy. Uwaga na pułapki: inna biblioteka C
  (musl), czasem inaczej działa `iconv` i sortowanie z `intl`.
- **Skaner:** `docker scout quickview sklep:bad` vs `sklep:prod`. Ile podatności (CVE) ubyło?
- **Przegląd warstw:** narzędzie `dive` (`docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive sklep:bad`).

## Sprzątanie
```powershell
docker rmi sklep:bad sklep:dev sklep:prod
docker builder prune      # czyści cache buildów (potrafi zajmować dziesiątki GB!)
```

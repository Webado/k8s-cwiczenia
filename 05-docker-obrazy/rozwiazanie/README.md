# Rozwiązanie lekcji 05 (spoilery!)

Żeby zbudować wzorcowy obraz: skopiuj `Dockerfile`, `.dockerignore` i `docker-entrypoint.sh` z tego folderu do `app/`.

## Wyniki referencyjne (zmierzone na Twoim komputerze, z 300 MB dumpem w `var/`)

| | `bad` | `prod` (rozwiązanie) |
|---|---|---|
| Rozmiar obrazu (`docker image inspect`) | **1479 MB** | **791 MB** (−46%) |
| Pierwszy build | 115 s | 60 s |
| Build po zmianie 1 linii kodu | 12 s (`composer install` od nowa) | **4 s** |
| Warstwa z kodem (`COPY . .`) | 315 MB (z dumpem!) | ok. 4 MB |
| Warstwa z `vendor/` | 144 MB (paczki dev + cache composera) | w tych ok. 4 MB |
| Warstwa z apt / rozszerzeniami | 192 MB + osobne warstwy | 80 MB |
| xdebug / paczki dev / display_errors | TAK / TAK / 1 | nie / nie / off |
| `docker stop` workera | ok. 3,5 s, exit **137** (SIGKILL), bez czystego zamknięcia | **0,4 s**, exit **0**, „Worker zakończony czysto” |

**Skąd pozostałe 791 MB?** Ok. 700 MB to sam obraz bazowy `php:8.3-apache` (Debian + Apache + PHP).
To, na co mieliśmy wpływ, zeszło z ok. 770 MB do ok. 85 MB. Dalsze odchudzanie wymaga zmiany bazy
(np. `php:8.3-fpm-alpine` + nginx), patrz bonusy w README.

**Build „po zmianie kodu” 12 s vs 4 s** wygląda niewinnie, bo nasza aplikacja ma kilkanaście paczek. W prawdziwym
projekcie Symfony z ponad 150 paczkami `composer install` to 1–3 minuty **przy każdym buildzie**, w CI i lokalnie.

## Grzechy złego Dockerfile'a i ich naprawy

| # | Grzech | Naprawa |
|---|---|---|
| 1 | Brak `.dockerignore`: dump bazy, testy, lokalny `vendor/` w obrazie | `.dockerignore` |
| 2 | `COPY . .` przed `composer install`: każda zmiana kodu = pełny install | najpierw `composer.json/lock` + install, potem `COPY . .` |
| 3 | `apt-get update` w osobnej warstwie (ryzyko nieaktualnego cache list pakietów) | `update` i `install` w jednym `RUN` |
| 4 | Sprzątanie apt w osobnym `RUN`: nic nie daje, warstwy są niezmienne | sprzątanie w tym samym `RUN` albo `install-php-extensions` |
| 5 | `vim`, `wget`, `git`, `curl`, biblioteki `*-dev` na produkcji | nie instalować, kompilować w osobnym kroku/etapie |
| 6 | xdebug na produkcji | tylko w targecie `dev` |
| 7 | `composer install` z paczkami dev | `--no-dev` w etapie `vendor` |
| 8 | composer w obrazie produkcyjnym | tylko w etapach `vendor` i `dev` |
| 9 | Brak `php.ini-production` i opcache | target `prod` |
| 10 | Entrypoint bez `exec`: PID 1 = sh, sygnały nie docierają do PHP | `exec php ...` / `exec apache2-foreground` |
| 11 | Worker dziedziczy `STOPSIGNAL SIGWINCH` z obrazu Apache'a | target `worker` z `STOPSIGNAL SIGTERM` |
| 12 | Brak cache composera między buildami | `RUN --mount=type=cache,...` |
| 13 | Ręczne `chmod +x` w osobnej warstwie | `COPY --chmod=755` |

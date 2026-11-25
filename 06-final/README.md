# Lekcja 06: FINAŁ. Incydenty + własne narzędzia w Claude Code

**Cel:** przećwiczyć dokładnie to, co będziesz robił od 1 grudnia: dostajesz zgłoszenie od supportu
(objaw, bez przyczyny), znajdujesz przyczynę, naprawiasz i opisujesz. Z pomocą AI, ale z Tobą jako tym,
kto decyduje. Do tego zbudujesz narzędzia z ogłoszenia: *„CLAUDE.md, skille, hooki”*.

---

## Część A: Dyżur 🚨

```powershell
cd 06-final
.\start-incydenty.ps1          # jeśli PowerShell blokuje: powershell -ExecutionPolicy Bypass -File .\start-incydenty.ps1
```
Odczekaj ok. 2 minuty.

### Zasady: co wolno czytać i zmieniać
| Plik / folder | Przed diagnozą | Po zapisaniu diagnozy |
|---|---|---|
| `_scenariusze/<plik incydentu>` | ❌ nie czytaj (tam jest przyczyna) | ✅ czytaj i **edytuj**, żeby wdrożyć poprawkę (`kubectl apply -f`) |
| `ROZWIAZANIA.md` | ❌ | ✅ po zapisaniu diagnozy **wszystkich** ticketów |
| `start-` / `stop-incydenty.ps1`, `README.md` | ✅ | ✅ |
| klaster (`kubectl`) | ✅ wszystko do odczytu | ✅ także zmiany w namespace'ach `incydenty*` |

Reset w dowolnym momencie (przywraca też zepsute wersje plików):
```powershell
git checkout -- _scenariusze/
.\stop-incydenty.ps1
.\start-incydenty.ps1
```

### Zasady dyżuru
- Incydenty **#1 i #2 rozwiąż sam**, bez AI. Sprawdzasz, ile już umiesz.
- Incydenty **#3–#5** możesz rozwiązywać z Claude Code (część B2: skill `/diagnoza-k8s`). Najpierw jednak zapisz
  **swoją hipotezę**, potem porównaj z tym, co znajdzie AI.
- Dla każdego zapisz: **objaw → przyczyna → dowód (komenda + wynik) → poprawka**.
- Po zapisaniu diagnozy naprawiaj w pliku danego scenariusza (patrz tabela wyżej) i `kubectl apply`. Na koniec
  sprawdź, że **objaw zniknął**. To, że pod jest zielony, nie wystarczy.

Pomocny pod do testowania z wnętrza klastra (udaje użytkownika): `kubectl exec -n incydenty ruch -- wget -q -O- http://<service>/`

---

### 🎫 Ticket #1 (priorytet: WYSOKI)
> **Od:** Support
> **Temat:** Klienci nie dostają maili z potwierdzeniem zamówienia
>
> Od mniej więcej godziny klienci piszą, że po złożeniu zamówienia nie przychodzi mail z potwierdzeniem.
> Zamówienia się zapisują, płatności przechodzą. Wcześniej działało. Namespace: `incydenty`.

### 🎫 Ticket #2 (priorytet: ŚREDNI)
> **Od:** Account manager
> **Temat:** Raport miesięczny nie dotarł do klienta
>
> Klient (duży bank) twierdzi, że raport miesięczny z dokumentami nie dotarł. Generuje się automatycznie w nocy.
> Podobno w zeszłym miesiącu też były problemy. Namespace: `incydenty`.
> *(W symulacji zadanie odpala się co minutę, a nie raz w miesiącu.)*

### 🎫 Ticket #3 (priorytet: ŚREDNI)
> **Od:** Zespół operacyjny
> **Temat:** Panel administracyjny strasznie muli
>
> Każda strona w panelu ładuje się po kilka sekund, czasem dłużej. Żadnych błędów, wszystko się w końcu ładuje.
> „Ktoś coś ostatnio zmieniał w konfiguracji?”. Namespace: `incydenty`, Service `panel`.

### 🎫 Ticket #4 (priorytet: WYSOKI)
> **Od:** Product owner
> **Temat:** Klienci nie widzą nowej wersji API
>
> Wczoraj wdrożyliśmy API v2 z eksportem do PDF. Klienci dalej dostają v1, bez nowej funkcji.
> Pipeline był zielony! Namespace: `incydenty`, Service `api`.

### 🎫 Ticket #5 (priorytet: KRYTYCZNY, jutro Black Friday)
> **Od:** Ops
> **Temat:** Sklep nie skaluje się przed Black Friday
>
> W ramach OPS-1432 przeskalowaliśmy sklep z 3 do 6 replik. Monitoring dalej pokazuje 3.
> Pody są zdrowe, żadnych restartów, żadnych Pending. Namespace: `incydenty-sklep`.

### A6. Post-mortem
Dla **jednego** incydentu (wybierz najciekawszy) napisz krótki post-mortem w `06-final/post-mortem.md`.
Taki dokument w firmach pisze się po każdej poważnej awarii, a przy L3 support to będzie Twoja robota:

```markdown
# Post-mortem: <tytuł>
**Wpływ:** kogo dotknęło, jak długo, co nie działało
**Oś czasu:** wykrycie → diagnoza → poprawka → potwierdzenie
**Przyczyna źródłowa:** (technika „5 x dlaczego”: dlaczego nie działało? A dlaczego TO? ...)
**Co pomogło / co przeszkadzało w diagnozie:**
**Działania naprawcze:** (poprawka + jak zapobiec: alert, test, review, zmiana procesu)
```
Zasada post-mortemów: **szukamy przyczyny w systemie, a nie winnego**. „Ktoś się pomylił” nie jest przyczyną.
Przyczyną jest „nic nie złapało pomyłki przed produkcją”.

---

## Część B: Własne narzędzia w Claude Code 🛠️

W repo są już dwie rzeczy, które dla Ciebie przygotowałem: **skill** i **hook**. Zrozum je, użyj ich,
a potem rozbuduj. Trzecią, czyli **CLAUDE.md**, napiszesz sam.

```
.claude/
├── settings.json                ← konfiguracja projektu (commitowana, wspólna dla zespołu)
├── settings.local.json          ← Twoje prywatne ustawienia (NIE do gita)
├── hooks/gitops-guard.ps1       ← skrypt hooka
└── skills/diagnoza-k8s/SKILL.md ← skill
```

### B1. CLAUDE.md: „instrukcja obsługi repo” dla AI
`CLAUDE.md` w głównym katalogu repo Claude Code czyta na początku **każdej** sesji. To jak onboarding nowego
członka zespołu: co to za projekt, jak tu pracujemy, czego nie wolno.

**Zadanie:** napisz `CLAUDE.md` dla tego repo (ok. 20–40 linii). Pomyśl, co powinien wiedzieć ktoś nowy:
- czym jest to repo i jaka jest struktura folderów,
- jakie są środowiska i konteksty (`docker-desktop`, namespace'y z Argo, a które są „do zabawy”),
- **zasady bezpieczeństwa** (GitOps, co tylko przez PR),
- jak sprawdzać zmiany przed commitem (`helm template`, `helm lint`, `terraform plan`...),
- konwencje (język, styl commitów), znane pułapki (PowerShell + Terraform, kodowanie, `>` w PS 5.1...).

Test: otwórz **nową** sesję Claude Code w repo i zapytaj „jak mam bezpiecznie zmienić liczbę replik na stagingu?”.
Czy odpowiedź uwzględnia Twoje zasady?

> W pracy CLAUDE.md w firmowym repo przeczytaj **pierwszego dnia**. Powie Ci o projekcie więcej niż niejeden onboarding.
> A jeśli go nie ma, to dobra okazja na pierwszy wartościowy PR.

### B2. Skill `/diagnoza-k8s`
Przeczytaj `.claude/skills/diagnoza-k8s/SKILL.md`. Skill to **procedura**, którą Claude ładuje, gdy jest potrzebna
(sam po opisie albo gdy wpiszesz `/diagnoza-k8s`). Dzięki niemu każda diagnoza idzie według tych samych kroków
i kończy się raportem w tym samym formacie.

Użyj go do ticketów #3–#5, np.:
```
/diagnoza-k8s Ticket: Panel administracyjny strasznie muli, każda strona kilka sekund, brak błędów. Namespace incydenty.
```
**Pytania:** czy Claude trzymał się procedury? Czy raport miał sens? Czy coś przeoczył albo przesadził?

**Zadanie:** popraw skill na podstawie tego, co zobaczyłeś. Np. dodaj krok specyficzny dla RabbitMQ
(długość kolejek, połączenia) albo zmień format raportu na taki, który wkleiłbyś do Jiry.

### B3. Hook `gitops-guard`
Przeczytaj `.claude/settings.json` i `.claude/hooks/gitops-guard.ps1`. Przed **każdą** komendą Bash/PowerShell,
którą chce wykonać Claude, Claude Code uruchamia ten skrypt. Skrypt może komendę **zablokować** i podać powód.
Pilnuje dwóch reguł:
1. `kubectl`/`helm` tylko na kontekście `docker-desktop`,
2. żadnych zmian kubectl/helm w `staging`, `production`, `argocd`, bo to obszar Argo CD i zmiany idą przez gita.

**Ważne:** hook pilnuje tylko komend **Claude'a**. Twojego terminala nie dotyka.

**Test:** poproś Claude'a: *„przeskaluj demo-web na stagingu do 4 replik”*. Co się stanie? Co Claude zrobi,
gdy hook go zablokuje? *(Powinien sam przejść na ścieżkę: zmiana w values → PR.)*

**Zadanie:** dodaj trzecią regułę, np. blokuj `terraform destroy` i `terraform apply` z `-auto-approve`.
Przetestuj na sucho, tak jak testuje się hooki:
```powershell
'{"tool_name":"Bash","tool_input":{"command":"terraform destroy -auto-approve"}}' | powershell -NoProfile -File .claude/hooks/gitops-guard.ps1
```
Pusty wynik = przepuszcza, JSON z `deny` = blokuje.

> Dlaczego hook, a nie po prostu instrukcja w CLAUDE.md? CLAUDE.md to **prośba**: model zwykle jej słucha,
> ale nie ma gwarancji. Hook to **twarda blokada**: wykonuje się zawsze, deterministycznie.
> Zasada: rzeczy „byłoby miło” idą do CLAUDE.md, a rzeczy „nigdy, pod żadnym pozorem” do hooka.

### B4. Finał: incydent → PR, end-to-end 🏁
To jest workflow z ogłoszenia: *„tworzenie workflow i agentów wspierających diagnozowanie błędów, przygotowywanie
poprawek i generowanie Pull Requestów”*.

1. **Zepsuj staging przez gita** (udajesz kolegę, który zrobił błąd). W `02-helm-argo/chart/values-staging.yaml` dodaj:
   ```yaml
   resources:
     requests:
       memory: 64Mi
     limits:
       memory: 32Mi
   ```
   Commit, push, Refresh w Argo. Co pokazuje Argo? (To nowy rodzaj awarii: nie pod, tylko **sync**.)
2. **Zleć Claude'owi całość** w jednym poleceniu, np.:
   > *Na stagingu demo-staging w Argo CD coś jest nie tak. Zdiagnozuj to skillem diagnoza-k8s, przygotuj poprawkę
   > na nowym branchu, wypchnij i otwórz PR przez gh z opisem przyczyny. Nie merguj.*
3. **Ty jesteś reviewerem.** `gh pr view`, `gh pr diff`. Czy poprawka jest dobra? Czy opis PR-a wyjaśnia przyczynę?
   Czy Claude nie próbował „naprawić” kubectl-em (i czy hook go zatrzymał)?
4. Merge (`gh pr merge --squash --delete-branch`), `git pull`, Refresh w Argo. `Synced` + `Healthy`?

---

## Sprzątanie
```powershell
.\stop-incydenty.ps1
```
Hook i skill zostaw: przydadzą się, a jako wzór możesz je przenieść do firmowego repo (po uzgodnieniu z zespołem).

# Lekcja 04: Terraform

**Cel:** czytać kod Terraform i, co najważniejsze, **czytać `terraform plan`**. Rozumieć state.
Umieć znaleźć w kodzie IaC rzeczy, które grożą wyciekiem danych, ich utratą albo awarią.

---

## 1. Gdzie jest Terraform w całej układance

```
┌─────────────────────────────────────────────────────────────────────┐
│ TERRAFORM   tworzy INFRASTRUKTURĘ: VPC, klaster EKS, nody EC2,      │
│             bazę RDS, S3, IAM, DNS... + "dodatki" klastra (Argo CD) │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │ ARGO CD + HELM   wdraża APLIKACJE do klastra (lekcja 2)     │   │
│   │   ┌─────────────────────────────────────────────────────┐   │   │
│   │   │ Twoja aplikacja PHP/Symfony                         │   │   │
│   │   └─────────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```
Zmienia się rzadko (raz w tygodniu/miesiącu), ale **błąd kosztuje dużo**: usunięta baza, otwarty port,
wyciek danych. Dlatego tu najważniejsze jest review, a nie szybkość.

### Terraform vs Kubernetes: ta sama idea, inne narzędzie
| | Kubernetes / Argo | Terraform |
|---|---|---|
| Opis stanu | YAML | HCL (`.tf`) |
| „Jak jest teraz” | klaster pamięta sam | **plik state** (`terraform.tfstate`) |
| Uzgadnianie | ciągle, automatycznie | tylko gdy ktoś zrobi `apply` |
| Podgląd zmian | `helm template`, APP DIFF w Argo | **`terraform plan`** |

---

## 2. Składnia HCL w 3 minuty

```hcl
variable "environment" { type = string }        # wejście  (jak values.yaml)

locals {                                         # zmienne pomocnicze
  namespace = "tf-${var.environment}"
}

resource "kubernetes_namespace_v1" "app" {       # resource "<TYP>" "<NAZWA>"
  metadata {
    name = local.namespace
  }
}

resource "kubernetes_config_map_v1" "infra" {
  metadata {
    namespace = kubernetes_namespace_v1.app.metadata[0].name   # REFERENCJA do innego zasobu
  }
}

output "namespace" {                             # wyjście (wypisywane po apply)
  value = kubernetes_namespace_v1.app.metadata[0].name
}
```
- **Kolejność w plikach nie ma znaczenia.** Terraform buduje graf zależności z **referencji**.
  ConfigMapa wskazuje na namespace, więc namespace powstanie pierwszy.
- **Nazwy plików nie mają znaczenia.** Terraform czyta wszystkie `*.tf` z folderu jako jedną całość.
  `main.tf`, `variables.tf`, `outputs.tf` to tylko konwencja.
- **Adres zasobu** = `<typ>.<nazwa>`, np. `kubernetes_namespace_v1.app`. Tak go zobaczysz w plan i state.

---

## 3. Cykl pracy i czytanie `plan`

```powershell
terraform init      # pobiera providery (jak composer install). Raz na start / po zmianie wersji
terraform plan      # CO SIĘ ZMIENI. Niczego nie dotyka. Bezpieczne zawsze
terraform apply     # pokazuje plan jeszcze raz i pyta "yes"
terraform destroy   # usuwa WSZYSTKO, czym zarządza ten state
```

### Symbole w planie: naucz się ich na pamięć
| Symbol | Znaczenie | Poziom strachu |
|---|---|---|
| `+` create | utworzy nowy zasób | 🟢 |
| `~` update in-place | zmieni zasób bez usuwania | 🟡 przeczytaj, co dokładnie |
| `-/+` replace | **USUNIE i utworzy od nowa** | 🔴 przy bazie/dysku/buckecie = **utrata danych** |
| `-` destroy | usunie | 🔴 |

Przy `-/+` Terraform pisze, który argument to wymusza: `# forces replacement`.
**Złota zasada:** jak w planie widzisz `-/+` albo `-` przy czymś, co trzyma dane (`aws_db_instance`, `aws_s3_bucket`,
`aws_ebs_volume`, namespace z PVC), zatrzymaj się i dopytaj.

---

## 4. State: najważniejsze i najbardziej niebezpieczne pojęcie

`terraform.tfstate` to plik JSON, w którym Terraform zapisuje: „zasób `aws_db_instance.main` z kodu
to w AWS baza o ID `db-ABC123`”. Bez state'u Terraform **nie wie, że cokolwiek już stworzył**.

W firmie state trzymany jest **zdalnie** (zwykle S3) z **blokadą (lock)**. Powody:
- cały zespół musi widzieć ten sam stan,
- dwa równoczesne `apply` mogłyby uszkodzić state albo infrastrukturę,
- **state zawiera sekrety w plain text** (hasła do baz, klucze). Nigdy nie commituj go do gita!

**Nigdy nie edytuj state'u ręcznie.** Do tego są komendy `terraform state ...` (i to też ostrożnie).

---

## ⚠️ PowerShell i Terraform

PowerShell rozbija argumenty z `=` i kropką. **Zawsze w cudzysłowie:**
```powershell
terraform plan -var-file=staging.tfvars       # ❌ Error: Too many command line arguments
terraform plan "-var-file=staging.tfvars"     # ✅
terraform plan "-var=web_replicas=3"          # ✅
```

---

## Część A: Ćwiczenia lokalne (`local/`)

Terraform zarządza Twoim lokalnym klastrem przez providery `kubernetes` i `helm`. Zero kosztów, zero AWS.
Przeczytaj najpierw wszystkie pliki w `local/`, mają komentarze.

```powershell
cd 04-terraform/local
```

**A1. Init.**
```powershell
terraform init
```
Co powstało? Zajrzyj do `.terraform/` (pobrane providery) i `.terraform.lock.hcl`.
`.terraform.lock.hcl` to odpowiednik `composer.lock`: **commituje się go**. `.terraform/` jest w `.gitignore`.

**A2. Plan i apply.**
```powershell
terraform plan "-var-file=staging.tfvars"
terraform apply "-var-file=staging.tfvars"
```
Ile zasobów utworzy? W jakiej kolejności je utworzył? (Dlaczego właśnie w takiej?)
Sprawdź efekt: `kubectl get all,resourcequota,configmap -n tf-staging`

**A3. State.**
```powershell
terraform state list
terraform state show kubernetes_resource_quota_v1.app
terraform output
```
Otwórz `terraform.tfstate` w edytorze (tylko popatrz!). Znajdź w nim swój namespace.

**A4. Zwykła zmiana.** W `staging.tfvars` zmień `web_replicas = 3`. `plan`: jaki symbol? Potem `apply`.

**A5. Drift: ktoś zmienił coś ręcznie.**
```powershell
kubectl patch configmap infra-config -n tf-staging --type merge -p '{\"data\":{\"DB_HOST\":\"zmienione-recznie\"}}'
terraform plan "-var-file=staging.tfvars"
```
Co pokazuje plan? Odpowiednik w AWS: ktoś „na szybko” zmienił Security Group w konsoli AWS.

**A6. Terraform nie widzi wszystkiego.** 👀
```powershell
kubectl scale deploy/demo-web -n tf-staging --replicas=5
terraform plan "-var-file=staging.tfvars"
kubectl get deploy -n tf-staging
```
Plan mówi `No changes`, a replik jest 5. Dlaczego Terraform tego nie widzi, skoro w A5 widział?
*(Hint: czym zarządza `helm_release`: Deploymentem czy „releasem Helma” z jego wartościami?)*
Co z tego wynika dla zdania: „plan pokazuje No changes, więc wszystko jest zgodne z kodem”?
Przywróć: `kubectl scale deploy/demo-web -n tf-staging --replicas=3`

**A7. Plan, którego NIE wolno zaaplikować. 🔴**
```powershell
terraform plan "-var-file=staging.tfvars" "-var=environment=production"
```
**Nie rób apply!** Tylko przeczytaj. Ile zasobów zostanie zastąpionych? Co wymusza zastąpienie?
Wyobraź sobie, że w tym samym kodzie jest `aws_db_instance` z nazwą zależną od `environment`. Co by się stało?

**A8. ResourceQuota w akcji.** W `staging.tfvars` ustaw `web_replicas = 20` i `apply`.
Apply będzie **wisieć do 5 minut** (Helm czeka, aż pody wstaną). W tym czasie w drugim terminalu:
```powershell
kubectl get pods -n tf-staging          # ile podów powstało? czy są Pending?
kubectl get resourcequota -n tf-staging
kubectl get events -n tf-staging --sort-by=.lastTimestamp | Select-Object -Last 5
```
Czym to się różni od `Pending` z lekcji 3? (Hint: czy brakujące pody w ogóle istnieją?)
Po błędzie apply przywróć `web_replicas = 2` i `apply`.

**A9. Utrata state'u. 💥**
```powershell
Move-Item terraform.tfstate $env:TEMP\ukryty.tfstate
terraform plan "-var-file=staging.tfvars"    # co Terraform chce zrobić?
terraform apply "-var-file=staging.tfvars"   # spróbuj. Co się stanie?
Move-Item $env:TEMP\ukryty.tfstate terraform.tfstate -Force   # przywrócenie
terraform plan "-var-file=staging.tfvars"    # wszystko wróciło?
```
Teraz wiesz, dlaczego state w S3 z wersjonowaniem to świętość.

**A10. Sprzątanie.**
```powershell
terraform destroy "-var-file=staging.tfvars"
```

---

## Część B: Code review prawdziwego kodu AWS (`aws-review/`) 🔍

To jest dokładnie zadanie z rozmowy: *„szukać w plikach IaC potencjalnych problemów i proponować usprawnienia”*.

W `aws-review/` jest kod infrastruktury produkcyjnej: **klaster EKS, baza MySQL (RDS), bucket S3 na dokumenty
klientów i uprawnienia IAM**. Kod jest poprawny składniowo (`terraform validate` przechodzi), ale
ma **kilkanaście problemów**: od „wyciek wszystkich danych klientów” po „drobne niedopatrzenie”.

**Nie uruchamiasz go** (wymaga konta AWS). Czytasz jak PR do review.

### Zadanie
1. Przeczytaj 4 pliki: `versions.tf`, `eks.tf`, `database.tf`, `storage.tf`.
2. Wypisz każdy problem z oceną wagi: 🔴 krytyczny / 🟠 ważny / 🟡 drobny. Dla każdego zapisz,
   **co może pójść źle** i **jak to naprawić**.
3. Podpowiedź, jakie kategorie sprawdzić:
   - 🔓 **Bezpieczeństwo:** kto może się dostać do czego? Skąd? Z jakimi uprawnieniami?
   - 💾 **Utrata danych:** co się stanie przy przypadkowym `destroy`, awarii albo pomyłce?
   - 🏥 **Dostępność:** co się stanie, gdy padnie jedna strefa AWS (AZ)? Czy da się skalować?
   - 🔧 **Utrzymanie:** wersje, state, powtarzalność.
   - Przypomnij sobie lekcję 3, pytanie 3 (pody w `Pending`, a autoscaler nodów)...
4. Porównaj z `aws-review/ROZWIAZANIA.md` (dopiero po!).

### Bonus: Ty vs AI
Po swojej analizie poproś Claude Code: *„Zrób security i reliability review kodu Terraform w 04-terraform/aws-review”*.
Porównaj: co znalazł on, a czego nie znalazłeś Ty? **Czy coś znalazł źle albo przesadził?**
Tak będzie wyglądała Twoja praca: AI robi pierwszą rundę, Ty oceniasz, co ma sens.

Istnieją też automatyczne skanery IaC (często podpięte w CI): **Trivy** (`trivy config .`), **Checkov**, **tfsec**.
Jak zobaczysz je w pipeline'ie w nowej pracy, będziesz wiedział, co robią.

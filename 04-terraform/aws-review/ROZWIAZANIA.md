# Rozwiązania: review kodu AWS (spoilery!)

## 🔴 Krytyczne

### 1. Baza danych dostępna z całego internetu
`database.tf`: `publicly_accessible = true` + Security Group `3306` z `0.0.0.0/0`
- **Ryzyko:** każdy w internecie może próbować logować się do produkcyjnej bazy. Boty skanują port 3306 non stop.
  Jedno słabe/wycieknięte hasło = wyciek wszystkich danych klientów.
- **Naprawa:** `publicly_accessible = false`. W SG ruch tylko z Security Group nodów EKS:
  ```hcl
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }
  ```

### 2. Hasło do bazy w kodzie
`password = "SuperTajneHaslo2024!"`
- **Ryzyko:** hasło jest w gicie (w historii **na zawsze**, nawet po usunięciu) i w state w plain text.
- **Naprawa:** `manage_master_user_password = true`. AWS sam wygeneruje hasło, trzyma je w Secrets Manager
  i rotuje. Aplikacja pobiera je przez External Secrets (lekcja 1). Hasło trzeba też **zmienić**, bo już wyciekło.

### 3. IAM `Action: "*"`, `Resource: "*"` na roli nodów
`storage.tf`
- **Ryzyko:** podwójne. (a) `*` na `*` = **administrator całego konta AWS**. (b) Polityka jest na roli **nodów**,
  więc dostaje ją **każdy pod** na każdym nodzie, łącznie z jakimkolwiek podatnym kontenerem. Włamanie do jednej
  apki = przejęcie całego AWS (usunięcie baz, kopii, kopanie krypto na koszt firmy).
- **Naprawa:** zasada najmniejszych uprawnień (tylko potrzebne akcje na konkretnym buckecie):
  ```hcl
  Action   = ["s3:GetObject", "s3:PutObject"]
  Resource = "${aws_s3_bucket.documents.arn}/*"
  ```
  I przypięcie **do konkretnej aplikacji**, a nie do nodów: **EKS Pod Identity** albo **IRSA** (rola IAM dla
  ServiceAccount z Kubernetesa, pamiętasz tabelkę z lekcji 1?).

### 4. Brak kopii zapasowych bazy
`backup_retention_period = 0` + `skip_final_snapshot = true` + `deletion_protection = false`
- **Ryzyko:** zero automatycznych backupów. Przypadkowy `terraform destroy` albo `-/+` w planie (lekcja A7!)
  = baza usunięta **bez ostatniego snapshotu**. Dane nie do odzyskania.
- **Naprawa:** `backup_retention_period = 7` (lub więcej), `skip_final_snapshot = false`
  z `final_snapshot_identifier`, `deletion_protection = true`. Dodatkowo w Terraformie:
  ```hcl
  lifecycle {
    prevent_destroy = true   # Terraform odmówi planu, który usuwa ten zasób
  }
  ```

### 5. Bucket z dokumentami klientów: `force_destroy = true`, brak wersjonowania
`storage.tf`
- **Ryzyko:** `force_destroy` pozwala Terraformowi usunąć bucket **razem z zawartością**. Brak wersjonowania =
  nadpisany/usunięty dokument (bug w kodzie, ransomware) przepada. Firma ma w ofercie „przechowywanie dokumentów
  o kluczowym znaczeniu”, więc to jest jej główny produkt.
- **Naprawa:** usunąć `force_destroy`, dodać `aws_s3_bucket_versioning` (Enabled), `prevent_destroy`,
  rozważyć Object Lock dla dokumentów z wymogami prawnymi/audytowymi, lifecycle na stare wersje.
  Jawnie dodać `aws_s3_bucket_public_access_block` (AWS domyślnie blokuje publiczny dostęp w nowych bucketach,
  ale jawna konfiguracja chroni przed tym, że ktoś to kiedyś wyłączy).

## 🟠 Ważne

### 6. State lokalny, brak backendu
`versions.tf`: brak bloku `backend`
- **Ryzyko:** state na laptopie jednej osoby (lekcja A9: zgubiony state = Terraform „zapomina” o całej
  infrastrukturze). Brak blokady = dwa równoczesne `apply`. State zawiera hasło z punktu 2.
- **Naprawa:** `backend "s3"` z `use_lockfile = true`, bucket z wersjonowaniem i szyfrowaniem.

### 7. Brak przypiętej wersji providera
`versions.tf`: `aws` bez `version`
- **Ryzyko:** `terraform init` za pół roku pobierze nową wersję główną z breaking changes. Plan nagle pokaże
  dziwne zmiany albo błędy.
- **Naprawa:** `version = "~> 6.0"` + commitowany `.terraform.lock.hcl`. Także `required_version` dla samego Terraforma.

### 8. Klaster EKS: API dostępne z całego internetu
`endpoint_public_access = true`, `public_access_cidrs = ["0.0.0.0/0"]`, `endpoint_private_access = false`
- **Ryzyko:** API Kubernetesa (to, z czym gada `kubectl`) wystawione na świat. Chroni je tylko uwierzytelnianie.
  Każda podatność w API albo wyciek tokena jest wykorzystywalny z dowolnego miejsca.
- **Naprawa:** `endpoint_private_access = true` i `public_access_cidrs` zawężone do VPN/biura,
  albo całkowicie prywatny endpoint + dostęp przez VPN.

### 9. Stara wersja Kubernetesa
`version = "1.29"`
- **Ryzyko:** dawno poza standardowym wsparciem AWS. Brak poprawek bezpieczeństwa, a **extended support jest płatny
  dodatkowo** (kilka razy drożej za klaster). Do tego aktualizacja EKS idzie tylko o jedną wersję naraz, więc dług rośnie.
- **Naprawa:** zaplanować upgrade (1.29 → 1.30 → ... po kolei, z testem na stagingu).
  To dokładnie „aktualizacje i bezpieczeństwo” z ogłoszenia.

### 10. Node group bez możliwości skalowania
`min_size = desired_size = max_size = 3`
- **Ryzyko:** lekcja 3, pytanie 3: HPA chce więcej podów, pody w `Pending`, a Cluster Autoscaler/Karpenter
  **nie może** dodać nodów, bo `max_size = 3`.
- **Naprawa:** np. `min_size = 3`, `max_size = 10`. Plus pułapka „dla seniora”: `desired_size` zmienia
  autoscaler, więc Terraform przy każdym planie chciałby go cofnąć (jak Argo vs HPA!). Rozwiązanie:
  ```hcl
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
  ```

### 11. Baza bez Multi-AZ, za mała i niezaszyfrowana
`multi_az = false`, `instance_class = "db.t3.micro"`, `storage_encrypted = false`
- **Ryzyko:** awaria jednej strefy AWS = produkcja leży, dopóki AWS jej nie podniesie. `t3.micro` (1 GB RAM,
  „burstable” CPU, które po wyczerpaniu kredytów zwalnia) na produkcji to proszenie się o problemy z wydajnością.
  Brak szyfrowania dysku łamie typowe wymogi compliance (RODO, ISO 27001, audyty klientów). Szyfrowania
  **nie da się włączyć** na istniejącej instancji: trzeba snapshot, skopiować go z szyfrowaniem i odtworzyć bazę.
- **Naprawa:** `multi_az = true`, klasa dobrana do obciążenia (np. `db.m7g.large`), `storage_encrypted = true`.
  Sprawdzić też wersję silnika: MySQL 8.0 w RDS wychodzi ze standardowego wsparcia, czyli znów płatny extended support.

## 🟡 Drobne

### 12. Brak tagów
Żaden zasób nie ma `tags` (environment, team, owner, cost-center).
- **Ryzyko:** nie da się rozliczyć kosztów („ile kosztuje nas staging?”), trudno znaleźć właściciela zasobu.
- **Naprawa:** `default_tags` w bloku `provider "aws"`, wtedy dotyczą wszystkich zasobów naraz.

### 13. `environment` z wartością domyślną `"production"`
`variables.tf`
- **Ryzyko:** ktoś zapomni podać zmienną i niechcący zrobi plan/apply na produkcję.
- **Naprawa:** bez wartości domyślnej (Terraform wtedy zapyta) + `validation` (jak w `local/variables.tf`).

### 14. Egress `0.0.0.0/0` na Security Group bazy
Baza nie musi sama nawiązywać połączeń z internetem. Drobne, ale częsty punkt w audytach.

---

## Jak oceniać wagę? Proste pytanie kontrolne
**„Co najgorszego może się stać i jak trudno to odkręcić?”**
- Wyciek danych / przejęcie konta / nieodwracalna utrata danych → 🔴
- Awaria, przestój, rachunek, dług techniczny, który da się naprawić → 🟠
- Porządek, wygoda, utrudnienia w przyszłości → 🟡

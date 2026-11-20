# Bucket S3 na dokumenty klientów ("dokumenty o kluczowym znaczeniu dla biznesu")
# + uprawnienia aplikacji do niego

resource "aws_s3_bucket" "documents" {
  bucket        = "platforma-dokumenty-${var.environment}"
  force_destroy = true
}

resource "aws_iam_policy" "app" {
  name = "app-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}

# Aplikacja działa na nodach EKS, więc dajemy uprawnienia roli nodów
resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.nodes.name
  policy_arn = aws_iam_policy.app.arn
}

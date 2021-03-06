resource "aws_sns_topic" "the-fixers-email" {
  name = "tf-the-fixers-email"
}

resource "aws_sns_topic" "the-fixers-sms" {
  name = "tf-the-fixers-sms"
}

data "external" "npm_install" {
  program = ["sh", "-c", "set -e; npm install > /dev/null; echo '{}'"]
}

data "external" "pack" {
  depends_on = [data.external.npm_install]
  program    = ["sh", "-c", "zip /tmp/statuspage_deploy.zip -FS -r node_modules *.js 1>&2 && node -e \"console.log(JSON.stringify({hash: crypto.createHash('sha256').update(fs.readFileSync('/tmp/statuspage_deploy.zip')).digest('base64')}))\""]
}

data "aws_kms_alias" "kms_production" {
  name = "alias/thegrommet/vault-production"
}

resource "aws_lambda_function" "statuspage" {
  depends_on       = [data.external.pack]
  filename         = "/tmp/statuspage_deploy.zip"
  source_code_hash = data.external.pack.result["hash"]
  handler          = "index.handler"
  role             = aws_iam_role.statuspage.arn
  description      = "Status Page"
  function_name    = "tf-statuspage"
  runtime          = "nodejs8.10"
  kms_key_arn      = data.aws_kms_alias.kms_production.target_key_arn

  environment {
    variables = {
      SMS_TOPIC         = aws_sns_topic.the-fixers-sms.arn
      EMAIL_TOPIC       = aws_sns_topic.the-fixers-email.arn
      SLACK_TOKEN       = data.aws_ssm_parameter.SLACK_TOKEN.value
      SLACK_CHANNEL     = data.aws_ssm_parameter.SLACK_CHANNEL.value
      JIRA_USER         = data.aws_ssm_parameter.JIRA_USER.value
      JIRA_PASSWORD     = data.aws_ssm_parameter.JIRA_PASSWORD.value
      JIRA_API_ENDPOINT = data.aws_ssm_parameter.JIRA_API_ENDPOINT.value
    }
  }
}

data "aws_ssm_parameter" "SLACK_TOKEN" {
  name = "statuspage.${terraform.workspace}.SLACK_TOKEN"
}

data "aws_ssm_parameter" "SLACK_CHANNEL" {
  name = "statuspage.${terraform.workspace}.SLACK_CHANNEL"
}

data "aws_ssm_parameter" "JIRA_USER" {
  name = "statuspage.${terraform.workspace}.JIRA_USER"
}

data "aws_ssm_parameter" "JIRA_PASSWORD" {
  name = "statuspage.${terraform.workspace}.JIRA_PASSWORD"
}

data "aws_ssm_parameter" "JIRA_API_ENDPOINT" {
  name = "statuspage.${terraform.workspace}.JIRA_API_ENDPOINT"
}

data "aws_iam_policy_document" "statuspage_assumerole" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "apigateway.amazonaws.com", "sns.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role" "statuspage" {
  name = "tf-statuspage"

  assume_role_policy = data.aws_iam_policy_document.statuspage_assumerole.json
}

data "aws_iam_policy_document" "statuspage_role" {
  statement {
    actions = [
      "sns:Publish",
    ]

    resources = [
      aws_sns_topic.the-fixers-email.arn,
      aws_sns_topic.the-fixers-sms.arn,
    ]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "statuspage" {
  name   = "tf-statuspage"
  role   = aws_iam_role.statuspage.id
  policy = data.aws_iam_policy_document.statuspage_role.json
}

resource "aws_api_gateway_rest_api" "statuspage" {
  name        = "statuspage"
  description = "The Grommet Status Page"
}

resource "aws_api_gateway_deployment" "production" {
  depends_on  = [aws_api_gateway_method.POST-statuspage-supportrequest]
  rest_api_id = aws_api_gateway_rest_api.statuspage.id
  stage_name  = "production"
}

resource "aws_api_gateway_resource" "statuspage-supportrequest" {
  rest_api_id = aws_api_gateway_rest_api.statuspage.id
  parent_id   = aws_api_gateway_rest_api.statuspage.root_resource_id
  path_part   = "supportrequest"
}

resource "aws_api_gateway_method" "POST-statuspage-supportrequest" {
  rest_api_id   = aws_api_gateway_rest_api.statuspage.id
  resource_id   = aws_api_gateway_resource.statuspage-supportrequest.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "OPTIONS-statuspage-supportrequest" {
  rest_api_id   = aws_api_gateway_rest_api.statuspage.id
  resource_id   = aws_api_gateway_resource.statuspage-supportrequest.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "OPTIONS-statuspage-supportrequest" {
  rest_api_id             = aws_api_gateway_rest_api.statuspage.id
  resource_id             = aws_api_gateway_resource.statuspage-supportrequest.id
  http_method             = aws_api_gateway_method.OPTIONS-statuspage-supportrequest.http_method
  integration_http_method = "OPTIONS"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.statuspage.invoke_arn
}

resource "aws_api_gateway_integration" "POST-statuspage-supportrequest" {
  rest_api_id             = aws_api_gateway_rest_api.statuspage.id
  resource_id             = aws_api_gateway_resource.statuspage-supportrequest.id
  http_method             = aws_api_gateway_method.POST-statuspage-supportrequest.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.statuspage.invoke_arn
}

resource "aws_lambda_permission" "allow_statuspage" {
  statement_id  = "tf-statuspage"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.statuspage.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.statuspage.execution_arn}/*/*/supportrequest"
}

resource "aws_cloudwatch_log_group" "statuspage" {
  name = "/aws/lambda/${aws_lambda_function.statuspage.function_name}"
}

data "aws_caller_identity" "current" {
}

data "aws_iam_policy_document" "allow_email_from_iam" {
  policy_id = "tf-the-fixers-email"

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "sns:Publish",
    ]

    resources = [
      aws_sns_topic.the-fixers-email.arn,
    ]

    sid = "tf-the-fixers-email-1"
  }
}

data "aws_iam_policy_document" "allow_sms_from_iam" {
  policy_id = "tf-the-fixers-sms"

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "sns:Publish",
    ]

    resources = [
      aws_sns_topic.the-fixers-sms.arn,
    ]

    sid = "tf-the-fixers-sms-1"
  }
}

resource "aws_sns_topic_policy" "email" {
  arn = aws_sns_topic.the-fixers-email.arn

  policy = data.aws_iam_policy_document.allow_email_from_iam.json
}

resource "aws_sns_topic_policy" "sms" {
  arn = aws_sns_topic.the-fixers-sms.arn

  policy = data.aws_iam_policy_document.allow_sms_from_iam.json
}

resource "aws_api_gateway_account" "statuspage" {
  cloudwatch_role_arn = aws_iam_role.statuspage.arn
}


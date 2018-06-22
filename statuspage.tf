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
  depends_on  = ["data.external.npm_install"]
  program = ["sh", "-c", "zip /tmp/statuspage_deploy.zip -FS -r node_modules *.js 1>&2 && node -e \"console.log(JSON.stringify({hash: crypto.createHash('sha256').update(fs.readFileSync('/tmp/statuspage_deploy.zip')).digest('base64')}))\""]
}

resource "aws_lambda_function" "statuspage" {
  depends_on  = ["data.external.pack"]
  filename         = "/tmp/statuspage_deploy.zip"
  source_code_hash = "${data.external.pack.result["hash"]}"
  handler          = "index.handler"
  role             = "${aws_iam_role.statuspage.arn}"
  description      = "Status Page"
  function_name    = "tf-statuspage"
  runtime          = "nodejs8.10"
}

data "aws_iam_policy_document" "statuspage_assumerole" {
  statement {
    actions = ["sts:AssumeRole"]

    principals = [
      {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com", "apigateway.amazonaws.com", ]
      },
    ]

    effect = "Allow"
  }
}

resource "aws_iam_role" "statuspage" {
  name = "tf-statuspage"

  assume_role_policy = "${data.aws_iam_policy_document.statuspage_assumerole.json}"
}

data "aws_iam_policy_document" "statuspage_role" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
      "logs:PutLogEvents",
      "sns:Publish",
    ]

    resources = [
      "arn:aws:logs:us-east-1:887971734956:log-group:/aws/lambda/tf-cloudwatch-notifications:log-stream:*",
      "${aws_sns_topic.the-fixers-email.arn}",
      "${aws_sns_topic.the-fixers-sms.arn}",
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

    resources = [ "*" ]
  }
}

resource "aws_iam_role_policy" "statuspage" {
  name   = "tf-statuspage"
  role   = "${aws_iam_role.statuspage.id}"
  policy = "${data.aws_iam_policy_document.statuspage_role.json}"
}

resource "aws_api_gateway_rest_api" "statuspage" {
  name        = "statuspage"
  description = "The Grommet Status Page"
}

resource "aws_api_gateway_deployment" "production" {
  depends_on = [ "aws_api_gateway_method.POST-statuspage-supportrequest" ]
  rest_api_id = "${aws_api_gateway_rest_api.statuspage.id}"
  stage_name  = "production"
}

resource "aws_api_gateway_resource" "statuspage-supportrequest" {
  rest_api_id = "${aws_api_gateway_rest_api.statuspage.id}"
  parent_id   = "${aws_api_gateway_rest_api.statuspage.root_resource_id}"
  path_part   = "supportrequest"
}

resource "aws_api_gateway_method" "POST-statuspage-supportrequest" {
  rest_api_id   = "${aws_api_gateway_rest_api.statuspage.id}"
  resource_id   = "${aws_api_gateway_resource.statuspage-supportrequest.id}"
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "POST-statuspage-supportrequest" {
  rest_api_id             = "${aws_api_gateway_rest_api.statuspage.id}"
  resource_id             = "${aws_api_gateway_resource.statuspage-supportrequest.id}"
  http_method             = "${aws_api_gateway_method.POST-statuspage-supportrequest.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:us-east-2:lambda:path/2015-03-31/functions/${aws_lambda_function.statuspage.arn}/invocations"
}

resource "aws_lambda_permission" "allow_statuspage" {
  statement_id  = "tf-statuspage"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.statuspage.function_name}"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.statuspage.execution_arn}/*/*/*"
}

resource "aws_cloudwatch_log_group" "statuspage" {
  name = "/aws/lambda/${aws_lambda_function.statuspage.function_name}"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "allow_email_from_iam" {
  policy_id = "tf-the-fixers-email"

  statement {
    effect = "Allow"

    principals = [
      {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
      },
    ]

    actions = [
      "sns:Publish",
    ]

    resources = [
      "${aws_sns_topic.the-fixers-email.arn}",
    ]

    sid = "tf-the-fixers-email-1"
  }
}

data "aws_iam_policy_document" "allow_sms_from_iam" {
  policy_id = "tf-the-fixers-sms"

  statement {
    effect = "Allow"

    principals = [
      {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
      },
    ]

    actions = [
      "sns:Publish",
    ]

    resources = [
      "${aws_sns_topic.the-fixers-sms.arn}",
    ]

    sid = "tf-the-fixers-sms-1"
  }
}

resource "aws_sns_topic_policy" "email" {
  arn = "${aws_sns_topic.the-fixers-email.arn}"

  policy = "${data.aws_iam_policy_document.allow_email_from_iam.json}"
}

resource "aws_sns_topic_policy" "sms" {
  arn = "${aws_sns_topic.the-fixers-sms.arn}"

  policy = "${data.aws_iam_policy_document.allow_sms_from_iam.json}"
}


resource "aws_api_gateway_account" "statuspage" {
  cloudwatch_role_arn = "${aws_iam_role.statuspage.arn}"
}

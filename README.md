# The Grommet Status Page

This repository contains both the static HTML frontend and the AWS Lambda backend for the service.

Configuration lives in AWS's SSM Parameter Store, encrypted with our KMS keys.  Running the terraform configuration in this repository will require credentials of an operator with access to that store.

## Installation and deployment

Install dependencies:

```
npm install
```

Deploy Lambda function:

```
terraform apply
```

The static HTML page:

```
npm run deploy
```

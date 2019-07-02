# service-health-dashboard
Service Health Dashboard using Route53 Health Checks

## Deployment

The project deploys automatically with CodeBuild. See the [buildspec.yml](.codebuild/buildspec.yml) file for build steps.

The CodeBuild project itself must be deployed from a local environment by running the [build script](.codebuild/build.sh).

This will deploy to the currently configured AWS account. 

```
$ cd .codebuild
$ ./build.sh service-health-dashboard
```

## Viewing the dashboard

After deployment view the dashboard at the `status.example.com` bucket domain name.

## Adding new health checks

Health checks are defined in the [Health Checks Terraform script](./provision/health-checks.tf). To add a new health check:

1. Open the script
1. Copy an existing health check resource
1. Change the configuration as required
1. Push the change
1. The change is deployed autoamtically.
1. The dashboard will update about 60 seconds after deployment completes

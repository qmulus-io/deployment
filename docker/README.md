Docker Cookbook
===============

This cookbook manages Docker and Docker-based applications.

Requirements
------------

This cookbook is intended to support deployments on AWS OpsWorks. It is designed to integrate into the default OpsWorks Chef repository, and depends on various components therein.

Usage
-----
#### docker::install

Installs Docker and sets Docker daemon to start automatically.

#### docker::deploy

Augments the standard AWS OpsWorks deployment recipe to deploy and start a Dockerized application. The application is expected to contain a Dockerfile in the base directory of its source repository. The following environment variables are required:

- **container\_port**: the port on which the application will listen (inside the container)
- **service\_port**: the public port that should be connected to the container port
- **layer**: the name of the AWS OpsWorks layer in which this application should run

Any other environment variables will be passed into the docker container and can be used to alter the behavior of the application.

The application is automatically started after it is deployed, and any previously-running version is automatically stopped and cleaned up.

#### docker::stop

Stops running docker applications.

This recipe will stop every dockerized application on the instance on which it runs. To stop only a specified application, pass a custom JSON with the `app` parameter, as in the following:

```
{
  "app": "NAME_OF_OPSWORKS_APPLICATION"
}
```

The application will be sent a SIGTERM immediately, and given 60 seconds to shut down gracefully, at which point it will be sent a SIGKILL.

#### docker::start

Starts running docker applications.

This recipe will start every dockerized application on the instance on which it runs. To start only a specified application, pass a custom JSON with the `app` parameter, as in the following:

```
{
  "app": "NAME_OF_OPSWORKS_APPLICATION"
}
```

#### docker::undeploy

Undeploys docker applications.

This recipe will undeploy every dockerized application on the instance on which it runs. To undeploy only a specified application, pass a custom JSON with the `app` parameter, as in the following:

```
{
  "app": "NAME_OF_OPSWORKS_APPLICATION"
}
```

This recipe will stop the application if it is running, remove its docker container and related image, and delete its source directory.

License and Authors
-------------------

**License:**

(c) 2014 Qmulus Inc.  
Apache License 2.0, except where noted.

**Authors:**

- Jeffrey Bagdis (jeff@qmulus.io)


Overview
========

This repository is intended to support and document the build and deployment infrastructure we use at Qmulus. It's taken a reasonable amount of effort to get a satisfactory environment set up, and there are a lot of (sometimes confusing and complicated) products out there from which to choose. We hope that anyone who is in a similar position will be able to benefit from this walkthrough as well -- whether you're just starting to develop an application and want a solid continuous integration environment right from the beginning, or whether you have an application in place and you're looking to improve the automation of your build, test, or deployment system.

Qmulus has combined the following tools and technologies into a simple deployment stack that works well for our needs:

- Docker (<https://www.docker.com>)
- Drone (<https://drone.io>)
- AWS OpsWorks (<http://aws.amazon.com/opsworks/>)
- Chef (<https://www.getchef.com>)

This document will walk through the complete process of setting up a continuous build and automatic deployment environment for a simple python web server application. 

Table of Contents
=================

- **[Overview](#overview)**
- **[The Application](#the-application)**
    - [Docker](#docker)
- **[Continuous Build](#continuous-build)**

The Application
==========

We will use the `Hello World` application contained in <https://github.com/qmulus-io/hello-world> as an example. This application is a simple Python web server that listens on port 8080 and serves a single index page with the message "Hello World."

The application should be able to run on just about any environment with the necessary Python modules installed. To run on your local environment, just check out the application repository (`git clone https://github.com/qmulus-io/hello-world`), and follow the instructions in the included README to configure and run it.

Docker
------

[Docker](<https://www.docker.com>) is a lightweight system for 'containerizing' an application, allowing it to run in a standard environment on top of many non-standardized platforms. It's quite powerful, and in some ways can be thought of like a version control system for infrastructures. We use it simply as an easy way to specify the complete set of requirements of each of our applications. Thus, our applications do not *need* to run in Docker, but we use Docker as a concise and portable way of describing each application's requirements, and of running our application wherever we want without making changes to the host system.

#### How we use Docker


Each of our applications is contained in a single Github repository. In the root of this repository is a [`Dockerfile`](https://docs.docker.com/reference/builder/) specifying the infrastructure that this application needs to run.

Our `Hello World` application uses a variant of the [`google/python-runtime`](https://registry.hub.docker.com/u/google/python-runtime/) Docker image. To do this, we copy the `Dockerfile` from that image to the base directory of our repository and add our tweaks. This is the contents of that file:

```
FROM google/python

WORKDIR /app
RUN virtualenv /env
RUN echo "source /env/bin/activate" >> ~/.bashrc

ADD requirements.txt /app/requirements.txt
RUN /env/bin/pip install -r requirements.txt
ADD . /app

CMD []
ENTRYPOINT ["/env/bin/python", "/app/main.py"]
```

This `Dockerfile` does the following:

- import the `google/python` Docker image, which provides a basic python environment.
- set the working directory to `/app`
- create a python virtual environment in `/env`
- add a line to root's `.bashrc` to activate that virtual environment whenever we drop into a shell
- copy the file `requirements.txt` fom the current directory (outside of Docker) into the image.
- run `pip` to install the packages required by the app.
- copy the rest of the app's repository into the docker image.
- set the entry point for running the application when Docker starts the container.

N.B. Docker creates a checkpoint image after every line that is cached for future re-use. This is why the `ADD . /app` line comes as late as possible. In this image, if the code has changed but not the `requirements.txt`, and the Docker image is build re-built on a system on which it has been built before, Docker will be able to re-use the cached image with the required python modules already installed, saving time and bandwidth.

With this configuration, we should be able to quickly build and run our app on any platform that has docker installed just by doing this:

```bash
git clone https://github.com/qmulus-io/hello-world

cd hello-world

docker build -t hello_world .

docker run -it --rm -p 80:8080 hello_world
  # will run interactively and listen on port 80 on the host machine
```

Continuous Build
================

So far we've used Docker to give us the ability to build and run anywhere with ease. The next thing we want to add to our build process is a continuous build server that will run all of our unit tests whenever anyone makes a push to Github. To do this, we've decided to user Drone.

Drone
-----

[Drone](<https://drone.io>) is an incredibly simple continuous build system with a cloud service that's free for open-source projects as well as a self-hosted version you can run on your own hardware and configure to your heart's content. We've decided to start with the cloud service, and more to the self-hosted system when we need to make advanced customizations.

N.B. Drone runs its automated builds inside of a Docker container, but the trick is it's not *your* Docker container, it's one of their standard ones. To be able to run our Drone builds inside our own Docker containers, the way our application runs at every other stage of our pipeline, we'll have to run our own Drone server and pull some crazy hacks like [this](http://stackoverflow.com/questions/24946414/building-docker-images-with-drone-io) on it. Right now, however, Drone's built-in containers are pretty much identical to ours, making this a project for another day.


#### How we use Drone


OpsWorks
--------

[AWS OpsWorks](http://aws.amazon.com/opsworks/) is a simple but powerful platform for managing and automating application provisioning and deployment on top of Amazon EC2. OpsWorks is the platform of choice for Qmulus's development, staging, and production environments, and this README is intended to document how we use OpsWorks internally, and serve as a simple tutorial or guide for anyone considering setting up a similar deployment environment with OpsWorks.

Chef
----

AWS OpsWorks uses [Chef](https://www.getchef.com) exclusively for all of its custom automation. Chef is quite powerful, but seems a bit heavy and complicated for our needs. We have tried to set up some basic Chef recipes 



Appendix
========

Docker on MacOSX
----------------

Docker runs natively on Linux. To use Docker on MacOSX, you'll need to run it inside a virtual machine of some kind. The simplest way to do this is to download [Boot2Docker](https://docs.docker.com/installation/mac/) -- a MacOSX app that packages a minimal Linux image running Docker inside VirtualBox, and takes care of all the setup and configuration for you.

##### 1. Installation

Download and run the latest `boot2docker.pkg` from [here](https://github.com/boot2docker/osx-installer/releases).

#####  2. Set-Up

Launch the `boot2docker` application from `/Applications`.

This will create a VirtualBox instance running the Docker daemon, and open up a shell with the necessary environment variables set to run `docker`. To set these environment variables in a new shell window, run

```
$(boot2docker shellinit)
```

##### 3. Using Docker

With `boot2docker` running, and the docker environment variables set, you can use the `docker` command to do anything you want. Docker containers will run inside the VirtualBox, so you'll have to connect to them via the VirtualBox's IP address. To find out what that is, run `boot2docker ip`

##### 4. Mounting host directories in Docker

For developing with Docker on MacOSX, you'll probably want to be able to mount a directory on your workstation (say, your GitHub repository) into your docker image, you can test code changes without having to rebuild the Docker image every time. To do that, you'll need to install VirtualBox Guest Additions into your boot2docker image, and connect `/Users` to the boot2docker VM. The easiest way to do that is the following:

Download <http://static.dockerfiles.io/boot2docker-v1.2.0-virtualbox-guest-additions-v4.3.14.iso>, then:

```bash
 # 1. Stop boot2docker and delete your current VM
 boot2docker destroy

 # Save the image you downloaded as ~/.boot2docker/boot2docker.iso
 
 # 3. Start boot2docker
 boot2docker init
 
 # 4. Pause boot2docker
 boot2docker stop
 
 # 5. Map the /Users/ directory into the virtual box
 VBoxManage sharedfolder add boot2docker-vm -name home -hostpath /Users
 
 # 6. Start boot2docker again
 boot2docker start
```

See [this post](https://medium.com/boot2docker-lightweight-linux-for-docker/boot2docker-together-with-virtualbox-guest-additions-da1e3ab2465c) for details.


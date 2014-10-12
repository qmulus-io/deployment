
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
    - [Drone](#drone)
- **[Production Deployment](#production-deployment)**
    - [OpsWorks and Chef](#opsworks-and-chef)
- **[Appendix](#appendix)**
    - [Docker on MacOSX](#docker-on-macosx)

The Application
==========

We will use the `Hello World` application contained in <https://github.com/qmulus-io/hello-world> as an example. This application is a simple Python web server that listens on port 8080 and serves a single index page with the message "Hello World."

The application should be able to run on just about any environment with the necessary Python modules installed. To run on your local environment, just check out the application repository (`git clone https://github.com/qmulus-io/hello-world`), and follow the instructions in the included README to configure and run it.

Docker
------

[Docker](<https://www.docker.com>) is a lightweight system for 'containerizing' an application, allowing it to run in a standard environment on top of many non-standardized platforms. It's quite powerful, and in some ways can be thought of like a version control system for infrastructures. We use it simply as an easy way to specify the complete set of requirements of each of our applications. Thus, our applications do not *need* to run in Docker, but we use Docker as a concise and portable way of describing each application's requirements, and of running our application wherever we want without making changes to the host system.

For some tips and tricks about running Docker on MacOSX, refer to [the Appendix](#docker-on-macosx).

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

[Drone](<https://drone.io>) is an incredibly simple continuous build system built on Docker with a cloud service that's free for open-source projects as well as a self-hosted version you can run on your own hardware and configure to your heart's content. We've decided to start with the cloud service, and more to the self-hosted system when we need to make advanced customizations.

N.B. Drone runs its automated builds inside of a Docker container, but the trick is it's not *your* Docker container, it's one of their standard ones (they have standard containers for many languages). To be able to run our Drone builds inside our own Docker containers, the way our application runs at every other stage of our pipeline, we'll have to run our own Drone server and pull some crazy hacks like [this](http://stackoverflow.com/questions/24946414/building-docker-images-with-drone-io) on it. Right now, however, Drone's built-in containers are pretty much identical to ours, making this a project for another day.


#### How we use Drone

Drone is incredibly simple to link to Github right out of the box. First, set up a Drone account on <http://www.drone.io> using your Github account. You'll automatically be able to connect to all of your repos.

Drone manages builds on a per-repo basis, regardless of what user added the repo to Drone. If you add a repo to your account that already exists in Drone, it seems like you'll get read-only access to the existing Drone configuration for that repo. You can then be added as an admin by the user who created the build.

If you don't have any repos configured for Drone yet, you'll see this screen. Click **"Setup your repos now"**. Otherwise, click **"New Project"** in the toolbar.

![](/images/drone00_welcome.png?raw=true)

Select your repository service (GitHub for us). You'll see a list of all the repositories in your account (including in your organizations). Click **"Select"** on the repo your want to build and test (for us, `qmulus-io/hello-world`).

![](/images/drone01_select_repo.png?raw=true)

Then you'll need to select the language of your project. This step is basically allowing you to select which of Drone's pre-built Docker images will be used to build your project. We're going to use Python.

![](/images/drone02_select_language.png?raw=true)

Now you need to tell Drone how to build your application, and how to run your tests. This will be substantially the same configuration as we've already specified in our `Dockerfile`, except for the part that runs the tests, and it's a shame that we have to semi-repeat it here.

![](/images/drone03_build_script.png?raw=true)

The default Python build script is good enough for now. It will install our app's custom requirements from `requirements.txt` and run our tests. We don't actually have any tests, so this will trivially succeed. Click **"Save"**

![](/images/drone03_build_script.png?raw=true)

And you're done! Drone automatically adds a hook to GitHub that will trigger a build whenever new code is pushed to your repo. You can trigger a manual build of any particular branch from here with the **"Build Now"** button, and from the **"Repository"** tab you can filter which branches will trigger an automatic build.

[Later on](#automated-deployment), we'll set up automatic deployment of each successful build to a "live" development environment on AWS, but first we're going to set up a basic production environment on AWS.

Production Deployments
======================

So far we've used Docker to encapsulate our application to run anywhere consistently, and Drone to do continuous builds. Our app is basically all dressed up with nowhere to go. Let's create a simple production environment on AWS on which to run our app. Then, we'll set up a stripped-down live development environment on the same infrastructure to which we can have Drone deploy each successful build.

We have chosen to use Amazon Web Services EC2 to host our applications, and AWS OpsWorks to manage our provisioning and deployment.

OpsWorks and Chef
-----------------

[AWS OpsWorks](http://aws.amazon.com/opsworks/) is a simple but powerful platform for managing and automating application provisioning and deployment on top of Amazon EC2. OpsWorks allows you to quickly describe an application stack consisting of various layers of application servers, database servers, and elastic load balancers. OpsWorks supports a handful of application server types out of the box, but this selection is quite limited. To deploy our Dockerized applications, we'll be using OpsWorks's 'custom' application server type.

OpsWorks uses [Chef](https://www.getchef.com) exclusively for all of its custom automation. Chef is quite powerful, but seems a bit heavy and complicated for our needs (after all, we chose Docker as a simple and lightweight tool to manage our infrastructure). However, we'll need to use a little bit of Chef as glue to make our custom OpsWorks layers run smoothly.

This repository contains some basic Chef recipes to turn the OpsWorks 'custom' server type into a pretty full-featured Docker application server, capable of running whatever Dockerized application we choose to throw at it (for now, we'll just be throwing `hello-world`, so that's not really so high a bar).

#### How we use OpsWorks

We're going to set up a simple OpsWorks stack, following along with [this official video tutorial](http://www.youtube.com/watch?v=9NnWJsS4Y2c#t=18), except instead of deploying a PHP application, we're going to set up our stack to run our Dockerized `hello-world` application. If you aren't familiar with OpsWorks, watch at least the first minute of the video before continuing. That will give you an overview of the basic theory and organization of OpsWorks; this walkthrough will follow the rest of the video pretty much verbatim, except for our custom changes to support Docker.

Let's start at the main [OpsWorks console](https://console.aws.amazon.com/opsworks/home#firstrun), which should look like this:

![](/images/opsworks00_welcome.png?raw=true)

Click **"Add Your First Stack"**.

Now you get to set a bunch of attributes for your stack. The defaults are mostly fine for our purposes. Here's what you'll need to change (click on **"Advanced"** at the bottom to see all the settings; you'll need them):

**Name:** Give you stack a name. We'll call ours `hello-world-prod`
**Default SSH Key:** Select an existing SSH key if you wan't to be able to SSH to your nodes for any reason (this seems like a useful idea especially as you're getting all the kinks worked out).
**Use custom Chef cookbooks:** Yes
 - **Repository URL:** Enter the URL to your Chef repository. (you can use this repository!) `https://github.com/qmulus-io/deployment.git`
 
That's it. Click **"Add Stack"**

You should see this -- the basic stack dashboard:

![](/images/opsworks01_add_layer.png?raw=true)

Next, let's follow Step 1 and add a layer to run our application servers. Click **"Add Layer"** and set the following options:

**Layer type:** Custom
**Name:** Give your layer a pretty, descriptive name with capitalization and everything. This is what will show up in your OpsWorks dashboard. We'll call ours `Web Server`.
**Short name:** Give your layer a programmatic identifier with no spaces or capitals (hypens will be converted to underscores in Chef recipes, so maybe avoid them.) We'll call ours `web_server`.

A note about the short name: Layers are designed to be used to segregate different types of applications in your stack. While nothing theoretically prevents you from running multiple different applications on the same layer, you can only run one application on each instance in that layer, and you won't have any programmatic way of telling them apart. Therefore, treat each layer as a pool of instances for a particular type of application server (if your app has multiple different types of servers working together) and use the short name to identify the specific server that will run in this layer. The short name will come back later when we get to deployments.

Click **"Add Layer"**

Now you have a layer, and the video walkthrough is going to want you to add instances. However, there's a little bit more configuration we need to do first. You should see this summary of your new layer:

![](/images/opsworks02_added_layer.png?raw=true)

Click **"Recipes"** This will open the details view for the layer's recipes. Click the **"Edit"** button at the top.

OpsWorks defines a five 'lifecycle events' for your instances (setup, configure, deploy, undeploy, and shutdown), and provides standard Chef recipes to perform those events when they are triggered. We're going to add some custom recipes to do the right things with Docker at each of these events.

Scroll down to the section titled **Custom Chef Recipes**.

![](/images/opsworks03_chef_recipes.png?raw=true)





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


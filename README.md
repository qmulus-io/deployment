
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
    - [How we use Docker](#how-we-use-docker)
- **[Continuous Build](#continuous-build)**
    - [Drone](#drone)
    - [How we use Drone](#how-we-use-drone)
- **[Production Environment](#production-environment)**
    - [OpsWorks and Chef](#opsworks-and-chef)
    - [How we use OpsWorks](#how-we-use-opsworks)
    - [Creating a Stack](#creating-a-stack)
    - [Creating a Layer](#creating-a-layer)
    - [Some Notes About Layers](#some-notes-about-layers)
    - [Creating an Application](#creating-an-application)
    - [Adding Instances](#adding-instances)
    - [Adding an Elastic Load Balancer](#adding-an-elastic-load-balancer)
- **[Application Lifecycle Events](#application-lifecycle-events)**
    - [Deploy](#deploy)
    - [Rollback](#rollback)
    - [Stop, Start, and Restart](#stop-start-and-restart)
    - [Undeploy](#undeploy)
- **[Continuous Deployment to Development Environment](#continuous-deployment-to-development-environment)**
- **[References](#references)**
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

How we use Docker
-----------------


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


How we use Drone
----------------

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

Production Environment
======================

So far we've used Docker to encapsulate our application to run anywhere consistently, and Drone to do continuous builds. Our app is basically all dressed up with nowhere to go. Let's create a simple production environment on AWS on which to run our app. Then, we'll set up a stripped-down live development environment on the same infrastructure to which we can have Drone deploy each successful build.

We have chosen to use Amazon Web Services EC2 to host our applications, and AWS OpsWorks to manage our provisioning and deployment.

OpsWorks and Chef
-----------------

[AWS OpsWorks](http://aws.amazon.com/opsworks/) is a simple but powerful platform for managing and automating application provisioning and deployment on top of Amazon EC2. OpsWorks allows you to quickly describe an application stack consisting of various layers of application servers, database servers, and elastic load balancers. OpsWorks supports a handful of application server types out of the box, but this selection is quite limited. To deploy our Dockerized applications, we'll be using OpsWorks's 'custom' application server type.

OpsWorks uses [Chef](https://www.getchef.com) exclusively for all of its custom automation. Chef is quite powerful, but seems a bit heavy and complicated for our needs (after all, we chose Docker as a simple and lightweight tool to manage our infrastructure). However, we'll need to use a little bit of Chef as glue to make our custom OpsWorks layers run smoothly.

This repository contains some basic Chef recipes to turn the OpsWorks 'custom' server type into a pretty full-featured Docker application server, capable of running whatever Dockerized application we choose to throw at it (for now, we'll just be throwing `hello-world`, so that's not really so high a bar).

We've been using the term 'application' to refer to single server program of whatever type (here it is a python web server that says "hello world" to visitors). A complex application may consist of several distinct types of servers -- web servers, api servers, database servers, etc. -- all working together. For consistency with OpsWorks's terminology, we're going to refer to this complete environment as a "stack" and each of the separate components within it as "applications". A stack may run several redundant instances of each application -- OpsWorks calls these groups of related instances "layers".

How we use OpsWorks
-------------------

We're going to set up a simple OpsWorks stack, following along with [this official video tutorial](http://www.youtube.com/watch?v=9NnWJsS4Y2c#t=18), except instead of deploying a PHP application, we're going to set up our stack to run our Dockerized `hello-world` application. If you aren't familiar with OpsWorks, watch at least the first minute of the video before continuing. That will give you an overview of the basic theory and organization of OpsWorks; this walkthrough will follow the rest of the video pretty much verbatim, except for our custom changes to support Docker.

The basis for our custom docker recipes came from this excellent blog post about [Running Docker on AWS OpsWorks](http://blogs.aws.amazon.com/application-management/post/Tx2FPK7NJS5AQC5/Running-Docker-on-AWS-OpsWorks). Consult that post for further information.

Creating a Stack
----------------

Let's start at the main [OpsWorks console](https://console.aws.amazon.com/opsworks/home#firstrun), which should look like this:

![](/images/opsworks00_welcome.png?raw=true)

Click **"Add Your First Stack"**.

Now you get to set a bunch of attributes for your stack. The defaults are mostly fine for our purposes. Here's what you'll need to change (click on **"Advanced"** at the bottom to see all the settings; you'll need them):

- **Name:** Give you stack a name. We'll call ours `hello-world-prod`
- **Default SSH Key:** Select an existing SSH key if you wan't to be able to SSH to your nodes for any reason (this seems like a useful idea especially as you're getting all the kinks worked out).
- **Use custom Chef cookbooks:** Yes  
    - **Repository URL:** Enter the URL to your Chef repository. (you can use this repository!) `https://github.com/qmulus-io/deployment.git`
 
N.B. Custom Chef cookbooks are automatically copied to each instance only once, when that instance is created. They are cached and are not pulled from the repository again, so any changes you make to them will not be reflected on any of your running instances. To get all your instances back up to date after a cookbook change, use the **"Update Custom Cookbooks"** command, in the **"Run Command"** tool, accessed from the **"Stack"** section of the OpsWorks console. Don't forget.
 
That's it. Click **"Add Stack"**

You should see this -- the basic stack dashboard:

![](/images/opsworks01_add_layer.png?raw=true)

Creating a Layer
----------------

Next, let's follow Step 1 and add a layer to run our application servers. Click **"Add Layer"** and set the following options:

- **Layer type:** Custom
- **Name:** Give your layer a pretty, descriptive name with capitalization and everything. This is what will show up in your OpsWorks dashboard. We'll call ours `Web Server`.
- **Short name:** Give your layer a programmatic identifier with no spaces or capitals (hypens will be converted to underscores in Chef recipes, so maybe avoid them.) We'll call ours `web_server`.

A note about the short name: Layers are designed to be used to segregate different types of applications in your stack. While nothing theoretically prevents you from running multiple different applications on the same layer, you can only run one application on each instance in that layer, and you won't have any programmatic way of telling them apart. Therefore, treat each layer as a pool of instances for a particular type of application server (if your app has multiple different types of servers working together) and use the short name to identify the specific server that will run in this layer. The short name will come back later when we get to deployments.

Click **"Add Layer"**

Now you have a layer, and the video walkthrough is going to want you to add instances. However, there's a little bit more configuration we need to do first. You should see this summary of your new layer:

![](/images/opsworks02_added_layer.png?raw=true)

Click **"Recipes"** This will open the details view for the layer's recipes. Click the **"Edit"** button at the top.

OpsWorks defines a five 'lifecycle events' for your instances (setup, configure, deploy, undeploy, and shutdown), and provides standard Chef recipes to perform those events when they are triggered. We're going to add some custom recipes to do the right things with Docker at each of these events.

Scroll down to the section titled **Custom Chef Recipes**, and add the following custom recipes:

![](/images/opsworks03_chef_recipes.png?raw=true)

- **Setup:** `docker::install`
- **Deploy:** `docker::deploy`
- **Undeploy:** `docker::undeploy`
- **Shutdown:** `docker::stop`

N.B. The Chef *Repository URL* is global for the whole stack, so you'll need to store all your custom Chef recipes for every layer in the same repo. For our purposes, though, the only recipes we'll need are these basic docker ones.

Click **"Save"**.

Some Notes About Layers
-----------------------

There is one peculiarity of OpsWorks layers that is important to know. Even though OpsWorks provides the useful distinction of "layers" to divide up groups of instances which each run a particular application in your stack, there's no built-in way to specify which application should run on which layer. Instead, OpsWorks seems to assume that you'll only ever have one layer of each type (i.e. PHP Server, Java Server, etc.), and uses these types to assign applications to layers. This would be fairly limiting even if we weren't intending to make all of our layers with the "custom" type.

To work around this, our `docker::deploy` Chef recipe can take a `layer` parameter (which we'll see later when we configure an application) that specifies the layer on which the application should run. The video walkthrough tells you to create some instances, then create an application, then deploy that application. In practice it's simpler to create the applications first, because whenever a new instance is created, OpsWorks will always attempt to deploy every application to it. Applications with the wrong type will be skipped by the default Chef deployment recipe, and docker application with the wrong layer specification will be skipped by our custom recipe. The nice parts of all this is that you never have to worry about (re)deploying the current version of your application after you spin up new instances to handle increased load, and that you don't have to uncheck all the other applications' layers when you manually deploy a new version of one application (they'll just get skipped automatically).

Creating an Application
-----------------------

We're going to skip ahead in the video a little bit and create an application before we create any instances. There is no wrong way, but if we have our applications defined first, they'll be automatically deployed when we spin up our instances (which is pretty cool).

Click **"Apps"** in the left bar. You should see this:

![](/images/opsworks04_no_apps.png?raw=true)

Click **"Add an app"** and set the following options:

- **Name:** Give your app a name. We'll call ours `web_server` (it's nice to name the app and its layer the same thing). This will also be the name given to the Docker image that gets built on each instance by the deployment recipe.
- **Type:** Other
- **Repository URL:** Enter the URL of the repo containing your app. `https://github.com/qmulus-io/hello-world.git`
- **Environment Variables:** You'll can set environment variables to control how Chef manages your Dockerized app. These are the ones you'll need. You can set additional ones and they'll be passed into your Docker container for your app to use if you want.
    - **container\_port:** The port on which your application server is listening, inside the Docker container. The `hello-world` server listens on port 8080.
    - **service\_port:** The port on the host which should be mapped to the container\_port. This port will be exposed to the outside world. We want expose our service on port 80.
    - **layer:** Here is where you specify the name of the layer on which this app should run. If you don't spell it right, the app will run nowhere. We called our layer `web_server`.

![The environment variables you'll need](/images/opsworks05_env_vars.png?raw=true)

Click **"Add App"**. You should see a summary entry for your new app.

![](/images/opsworks06_app_added.png?raw=true)

Adding Instances
----------------

Now we'll pick back up with the video walkthrough and add some instances. Click **"Instances"** in the left bar. You should see a summary of each layer, showing its current instances. Since you have one layer and no instances, you'll get this:

![](/images/opsworks07_no_instances.png?raw=true)

Click **"Add an instance"**. The default options are fine, though `hello-world` probably doesn't neem a `c3.large`. We'll use an `m1.small` instead.

![](/images/opsworks08_add_instance.png?raw=true)

N.B. In **Advanced**, if you set the **Root device type** to `Instance store` (the default stack default), then the instance's storage will be deleted every time it stops, which is cheaper than the alternative and probably what you want anyway for a stateless application server.

Click **"Add Instance"**. Let's follow the video walkthrough and add a second instance just like the first. After that, you should be here:

![](/images/opsworks09_stopped_instances.png?raw=true)

Click **"Start All Instances"**. It will take a few minutes for AWS to provision all your instances.

Adding an Elastic Load Balancer
-------------------------------

The video walkthrough talks about using HAProxy to distribute load between the instances in a layer. However, the standard HAProxy configuration on OpsWorks doesn't support play nicely with our custom layer type, and configuring it requires a decent amount of hacking around with Chef. An alternative is to use AWS's Elastic Load Balancer service, which is simpler and more robust but less flexible than HAProxy. [This post](http://harish11g.blogspot.com/2012/11/amazon-elb-vs-haproxy-ec2-analysis.html) provides an excellent comparison.

We'll need to create an ELB instance in EC2 to use with our OpsWorks stack (technically, with our  OpsWorks *layer*, because each layer will need it's own ELB if it's going to need one at all). 

To add an ELB, we'll need to switch to the EC2 console. Click **"Layers"** in the left column, then click **"Network"** in the layer summary. Click **"Edit"** on the top right. There should be a link to the [**"EC2 Console"**](https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#LoadBalancers:) in the **Elastic Load Balancing** section. Click **"Create Load Balancer"** and you'll find yourself at this wizard:

![](/images/elb00_create.png?raw=true)

Give your load balancer a name, sensibly the same name as your OpsWorks stack (with an appended layer identification if you'll be exposing multiple layers to the world). Also, specify what ports to expose. We're just going to use port 80 for `hello-world`. Click **"Continue"**.

![](/images/elb01_health.png?raw=true)

Health Check is how your ELB determines which instances are alive and capable of handling traffic. The default settings are almost perfect, but we'll need to change the **Ping Path** to `/`, because `hello-world` doesn't have an `index.html`. Click **"Continue"**.

Just click **"Continue"** through the rest of the wizard. We don't want to add any instances now because OpsWorks will take over managing the load balancer once we link them together.

![](/images/opsworks10_load_balancer.png?raw=true)

With a load balancer created, we can now link it to our OpsWorks layer. Switch back to the OpsWorks console (where we were in the middle of editing the network settings for our layer) and select the new load balancer from the drop-down menu.

![](/images/opsworks11_layer_elb.png?raw=true)

Click **"Save"**.

Now, back in the **Layers** summary view, you'll see an ELB instance attached to your layer. Once all your instances have passed enough health checks, which could take a few minutes, and all the badges are green, your app is up and running. Click on the ELB url to actually load the app, see our "Hello World" message in all its glory. (We can also go straight to any particular instance, using its IP from the **Instances** screen, and see the page served by that particular server, bypassing the ELB, if we want to.)


Application Lifecycle Events
============================

So we've build a simple fault-tolerant and scalable production environment with AWS OpsWorks. What now? Well, assuming our app is ever going to be worked on again, we're going to have to deploy a new version at some point. Now, this is our production environment, so of course we're not going to be deploying any releases that haven't gone through the testing and QA and all of that. Deploying to production should be done manually, after due consideration, but it should also be done with a single button push, and we should be able to roll back right away if there's a problem (with but a second button push).

OpsWorks makes this, almost, a piece of cake.

Deploy
------

Deploying a new version of an app *is* a piece of cake. Switch to the **"Apps"** summary screen on the OpsWorks console.

![](/images/opsworks12_apps.png?raw=true)

Click **"deploy"** for the app you want to update.

![](/images/opsworks13_apps.png?raw=true)

You don't need to set any options on this screen, just click **"Deploy"** and your app will roll out to every instance in the appropriate layer. (Technically, it will be sent to every instance in every layer, but Chef will skip deploying it on instances that don't match the app's `layer` value we set up when we created the app.) If you only want to deploy to some instances in your app's layer, for a gradual roll-out say, then select instances with the **"Advanced"** view, but otherwise just push it to every instance and let Chef sort it out.

You'll notice that there are a bunch of commands other than **Deploy** for you to choose from on this screen. Most of these, however, will only work for the particular application types that OpsWorks natively supports, and will have no effect on our custom layers. Only **Deploy** and **Undeploy** here will actually do anything, but we've set up custom Chef recipes to perform the other functions in a slightly different way.

Rollback
--------

OpsWorks lets you roll back up to 5 deployed versions. However, this only works for the native application types, and I haven't written a rollback recipe for Docker yet. Right now we can't roll back with OpsWorks directly, and instead have to re-deploy a previous version (by reverting our repository and deploying as for a new version) when we want to roll back a failed release.

**TODO:** make rollback work more smoothly.

Stop, Start, and Restart
------------------------

Since we can't use OpsWorks build in deployment commands for these operations, we've built some simple Chef recipes to do them for us. Switch to the **"Deployments"** section of the OpsWorks console, and click the **"Run Command"** button.

![](/images/opsworks14_deployments.png?raw=true)

**Run Command** lets you do a bunch of tasks on the stack that are not (ostensibly) application-specific, like the **Update Custom Cookbooks** command we mentioned earlier. To stop, start, or restart a Docker application on some instances, we're going to use the **Execute Recipes** command.

![](/images/opsworks15_stop.png?raw=true)

We have two ways to specify what applications to affect. Either we can limit the command to only run on certain layers or instances, or we can pass Chef a custom JSON telling it which app to modify (or we can do both). This is what the custom JSON should look like (where `web_server` is the name of our application):

```
{
 "app": "web_server"
}
```

If the custom JSON is not specified, the recipe will affect any Docker app running on the included instances.

##### Stop

To stop an application, use this recipe:

```
docker::stop
```

##### Start

To start a stopped application, use this recipe:

```
docker::start
```

##### Restart

To restart a running application, use the two recipes together:

```
docker::stop, docker::start
```

You can provide a comment describing what app you're affecting, and what you're doing to it that will show up in the deployments summary and make the history of the stack much clearer than just a whole bunch of "Execute Recipes". You can also re-run past deployments/commands from the deployments summary screen, so if you label your custom executions, you won't have to type the recipe names every time you do common tasks.

Undeploy
--------

Undeploy is actually a lifecycle event, so our custom `docker::undeploy` recipe is registered in the layer settings like our custom `docker::deploy` recipe. This means you can do undeploys the same way as deploys, and the same way you would for a non-custom application on OpsWorks.

Continuous Deployment to Development Environment
================================================

The last piece of the puzzle is to set up a development environment that mirrors our production stack as much as possible, and configure Drone to automatically deploy every new build to this environment, so we have a place to do integration testing that's always as up-to-date as possible.

To do this, we're going to start by creating a new stack on OpsWorks, called `hello-world-dev`, exactly the same way as we created our production stack, with two important exceptions.

2. We're only going to create a single instance in each layer in our development stack. This instance will:
    - Have an EBS volume, so it's state won't disappear when it stops (you'll see why in a minute).
    - Have an Elastic IP, so we can point a DNS name directly at it.
    - Be as small as possible (for our app's needs), since it's development and not production.
1. We're not going to configure an Elastic Load Balancer. We're going to access the single instance in each layer directly via its own Elastic IP, instead of pooling them behind an ELB.

I'm going to finish this section after dinner, because I've written a lot today already.

TODO: deploy only `master` branch.

TODO: Clone stack from [OpsWorks Console](https://console.aws.amazon.com/opsworks/home?#/dashboard).


References
==========

- [Docker Explained - How to Containerize Python Web Applications](https://www.digitalocean.com/community/tutorials/docker-explained-how-to-containerize-python-web-applications)

- [Remove Untagged Images from Docker](http://jimhoskins.com/2013/07/27/remove-untagged-docker-images.html)

- [Docker - Managing Data in Containers](http://docs.docker.com/userguide/dockervolumes/)

- [Building Docker Images with Drone.io](http://stackoverflow.com/questions/24946414/building-docker-images-with-drone-io)

- [Software Delivery via Amazon Docker Workflow](http://r.32k.io/adf)

- [How We Use Docker for Continuous Delivery - Part 1](http://contino.co.uk/use-docker-continuously-deliver-microservices-part-1/) 

- [Getting Started with AWS and OpsWorks (video)](http://www.youtube.com/watch?v=9NnWJsS4Y2c#t=18)

- [Running Docker on AWS OpsWorks](http://blogs.aws.amazon.com/application-management/post/Tx2FPK7NJS5AQC5/Running-Docker-on-AWS-OpsWorks)

- [OpsWorks - Cookbooks 101](http://docs.aws.amazon.com/opsworks/latest/userguide/cookbooks-101.html)

- [OpsWorks - Updating Custom Cookbooks](http://docs.aws.amazon.com/opsworks/latest/userguide/workingcookbook-installingcustom-enable-update.html)

- [OpsWorks - Use Custom JSON to Modify the Stack Configuration JSON](http://docs.aws.amazon.com/opsworks/latest/userguide/workingstacks-json.html)

- [Comparison Analysis:Amazon ELB vs HAProxy EC2](http://harish11g.blogspot.com/2012/11/amazon-elb-vs-haproxy-ec2-analysis.html)

- [Boot2docker together with VirtualBox Guest Additions](https://medium.com/boot2docker-lightweight-linux-for-docker/boot2docker-together-with-virtualbox-guest-additions-da1e3ab2465c)


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

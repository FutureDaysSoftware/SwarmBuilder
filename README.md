# SwarmBuilder
A set of Bash scripts to build a web hosting environment using Docker Swarm.

## Configuration

**The config file**

The `config.example.sh` script is a template for the config file that this script requires.
A file named `config.sh` must exist before the scripts will run properly.  If the config file doesn't
exist, it will be created when the `swarmbuilder.sh` script is run by making a copy of the
`config.example.sh` file.

The config file holds your Digital Ocean API key and settings for creating new droplets.
If you don't specify an API key in the config file, then it must be provided on the command line
when running the `swarmbuilder.sh` script by passing the `-t` or `--token` argument.

    $ swarmbuilder.sh create exampleSwarmName --token <mySuperLongApiKey>

If a DigitalOcean API key is set in your `config.sh` file and you also provide one on the
command line (with the `--token` argument), the one given on the command line will be used instead
of the one in your config file.

**Adding swarmbuilder to your path**

An install-script is included that will symlink the swarmbuilder.sh script into your `~/bin/` folder
and ensure that the folder is in your path.

    $ cd swarmbuilder
    $ ./install-link.sh

Once this is done, you can run the swarmbuilder script from inside any folder without providing the path.
Also, the `.sh` file extension is omitted when using the symlinked command.

## Usage

### Creating a New Swarm
To create a swarm with 3 nodes (1 manager & 2 workers) on droplets named `exampleSwarmName-1`, 
`exampleSwarmName-2`, and `exampleSwarmName-3` that will be publicly accessible at https://mydomain.com.  
The application Stack defined by `docker-compose.yml` will then be deployed to the Swarm and will be named
`webApp`:
	
    $ swarmbuilder.sh create exampleSwarmName \
        --domain mydomain.com \
        --workers 2 \
        --tls \
        --compose-file ./docker-compose.yml \
        --stack-name webApp
        
### Changing the number of workers in the swarm
Add or remove worker nodes from the swarm.

    $ swarmbuilder.sh scale-swarm exampleSwarmName --workers 5
    
*Note that scaling the number of managers is not currently supported.*

### Scaling a service stack
Increase or decrease the number of replicas of your web app).
This command only changes the number of replicas of the service named ‘web’ (by convention), defined in the application’s docker-compose.yml file:
When increasing the number of replicas, additional worker nodes will be created to prevent
any one node from running more than 1 replica of the same service.
Nodes will not be deleted when decreasing the number of replicas.

    $ swarmbuilder.sh scale-stack exampleSwarmName --stack-name webApp --replicas 3
    
### Removing a service stack
To completely remove a service stack from the swarm, use:

    $ swarmbuilder.sh remove-stack exampleSwarmName --stack-name webApp

There is an optional `--force` flag that can be used to bypass the interactive confirmation.

### Deploying & updating application code in the swarm
Deploying a new stack to the swarm uses the same command as updating the code on an existing stack.
When the application code has been updated, a new docker image must be built and pushed to the 
Docker registry before the swarm can be updated.  Once the image is available through the registry,
 updating the swarm can be done like this:

    $ swarmbuilder.sh deploy exampleSwarmName \
        --compose-file ./docker-compose.yml \
        --stack-name webApp

*Note: this requires that the naming conventions for services in the `docker-compose.yml` file be followed.*
Behind the scenes, SwarmBuilder will look on the swarm named `exampleSwarmName` for a stack of services that is also named `exampleSwarmName` and update the stack with the provided `docker-compose.yml` file.
    
### Destroying the swarm
To destroy the entire swarm and associated DigitalOcean droplets:

    $ swarmbuilder.sh destroy exampleSwarmName 

## Known Issues

#### You receive the error: `Error: fork/exec /usr/bin/ssh: permission denied`
This error is caused by a faulty installation of the `doctl` command-line tool.
The issue is known to exist in doctl v1.7.0 when installed using the `snap`
package manager (`sudo snap install doctl`).
The error is resolved by installing `doctl` directly from a GitHub release.
  
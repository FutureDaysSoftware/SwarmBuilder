# SwarmBuilder
A set of Bash scripts to build a web hosting environment using Docker Swarm.

## Usage

### Creating a New Swarm
To create a swarm with 3 nodes (1 manager & 2 workers) on droplets named `exampleSwarmName-1`, `exampleSwarmName-2`, and `exampleSwarmName-3` that will be publicly accessible at https://mydomain.com.  The application Stack defined by `./docker-compose.yml` will then be deployed to the Swarm:
	
    $ swarmbuilder.sh create exampleSwarmName $DO_API_KEY \
        --domain mydomain.com \
        --managers 1 \
        --workers 2 \
        --tls \
        --deploy ./docker-compose.yml
        
### Changing the number of workers in the swarm
Add more worker nodes to the swarm (and subsequently increase the replicas of your web app).  This command only changes the number of replicas of the service named ‘web’ (by convention), defined in the application’s docker-compose.yml file:

    $ swarmbuilder.sh scale exampleSwarmName $DO_API_KEY --workers 5
    
*Note that scaling the number of managers is not currently supported.*

### Updating application code in the swarm
When the application code has been updated, a new docker image must be built and pushed to the Docker registry before the swarm can be updated.  Once the image is available through the registry, updating the swarm can be done like this:

    $ swarmbuilder.sh update exampleSwarmName $DO_API_KEY --deploy ./docker-compose.yml

*Note: this requires that the naming conventions for services in the `docker-compose.yml` file be followed.*
Behind the scenes, SwarmBuilder will look on the swarm named `exampleSwarmName` for a stack of services that is also named `exampleSwarmName` and update the stack with the provided `docker-compose.yml` file.
    
### Destroying the swarm
To destroy the entire swarm and associated DigitalOcean droplets:

    $ swarmbuilder.sh destroy exampleSwarmName $DO_API_KEY


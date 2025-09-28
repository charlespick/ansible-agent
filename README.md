# Ansible Agent
* Kubernetes workload you can run right alongside your AWX and AWX Operator
* Lightweight Python app with no authentication so you can easily have your VMs callback for provisioning after being created
* Lightweight "agent" on your host that calls back for configuration at staggered intervals, similar to a configuration management agent

## What it does
* Listens for HTTP calls to request provisioning/drift correction
* Calls the AWX API to start a given workflow or template with a limit

## How is this secure?
Even though the endpoint is unauthenticated, this system remains secure because
* Calls are HEAVILY rate limited. A single IP can only make 1 call every 5 minutes by default.
* You can define a global rate limit as well in the config.
* The credentials you provide to the relay service should be very low privleged.
* The hostname provided in the API call is sanitized, trimmed, checked for obscure characters not expected in computer hostnames, and checked for obscene lengths before being passed off to the AWX API
* You define a single template/workflow that will be launched using the API, limited to a single host
* The host you limit the AWX Job run with still needs to exist in inventory, and be resolvable with DNS. This service does not add arbitrary hosts to your inventory.

## How it's deployed
Because most AWX installations now require the AWX operator, it makes sense to put your agent service on K8s as well. You'll deploy the app to K8s using variables
* `awx-api-endpoint`
* `awx-template-name` OR
* `awx-workflow-name`
* `global-rate-limit`
* `per-ip-rate-limit`
* Credentials via K8s Secrets

Deploy using the same load balancer/ingress/cert management you deployed your AWX with. Because there is no state to this service, it can scale freely and simply if needed. 

## Installing the agent
The Agent runs on Linux and Windows hosts managed by Ansible. You can install it with an Ansible playbook or the script. 
* Runs at the cadence specified in the conf file
* The exact execution time within each period is determined by a hash of the hostname. This ensures your AWX instance isn't slammed every hour on the hour (or at midnight, etc)
* Simply makes a call to the relay service with the local hostname. The relay and AWX takes it from there. 

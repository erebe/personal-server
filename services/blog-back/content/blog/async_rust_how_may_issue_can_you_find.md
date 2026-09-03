+++
title = "Async Rust: How many issue can you find ?"
description = "Try your luck and see if you are an expert in asynchronous rust programming !"
date = 2022-09-04
[extra]
header = '''<iframe width="560" height="315" src="https://www.youtube.com/embed/3LQlaAkmfNk" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>'''
tags = ["rust", "async", "rust async hard", "hard"]
+++

<p style="border-style: double; padding: 5px 0px 5px 5px">
tl;dr:
<br/>
  - Async Rust is hard, yes, but this is not the first difficulty
<br/>
  - First, you need to learn to think differently while using async/reactive programming
</p>


[Reddit discussion](https://www.reddit.com/r/rust/comments/nvpkx4/buildkit_speed_up_your_rust_ci_build_by_using/)

--- 

...

*You turn on your computer while sipping a coffee and got attacked by a wild colleague eager to release a new project.*

*You know him, you heard his team is already way beyond their deadline, which have been postponed already twice. They thought at first including a blockain would have made things easier, no single point of failure. Maybe this is the new wave of the 2000 era where everybody wanted to use a DHT with his torrent protocol. Sadly it didn't work out, but marketing made some nice blogposts about it with Web3 being the future of the company, they got some juicy SEO.*

*So they moved to use serverless AWS lamda in the cloud. Still no single point of failure, and after some configuration wizardry, divine incantation, multiple requests to support and a demo to management, finance told them NO. The project should stay under strict budget, and you can heard the piggy bank of a child in Africa being molested by abusive parents to pay the bill every time you launch a lambda. Legal departement joined side with finance as they wanted to avoid associating the company in anyway with that image, they missed the joke I think.* 

*Then, somebody in the team proposed to do something a bit arcane, write an app with an infinite loop and some wait in the middle, or the beginning, can't remember properly the gossip or he was not sure himself. Even if not convinced, the team lead put the idea to debate to not appear deminishing his colleague idea. In the end it sticked, but only shortly ahead from writing a lua script in Nginx that a devops knew how to do it from a mailing list.*

*This research project is written in Rust. You hint that it was a major factor from the decision of not using the lua script in nginx, but the team lead convinced management by explaining performance was a requirement from the start. The app has to handle at peak business traffic 3.628.800 requests per day and no garbage collector language was mandatory because the Australian target audience, who already have to reach the single instance running in us-east-2, would suffer from the induced latency*

*__Disclamer__*: While I don't think the child in Africa with abusive parents need one, I would like to disclaim the fact that I ❤️ writing in Rust, his ecosystem, the people around it and I am forever in debt to the ones smarter than me that created a viable alternative to Go monstruous type system. 

--- 


<ins>**Xavier**</ins>: Morning Charles ! Can you please review this PR. This is the last one to be able to release our reverse proxy that is supposed to manage our fleet a IOT devices

<ins>**Charles**</ins>:  Hi Xavier, can you see this with your team please ? I am pretty busy at the moment with other projects. I have this one that is supposed to be already finished...

<ins>**Xavier**</ins>: but... you are our team lead...

<ins>**Charles**</ins>: Haha right... I forgot, remote working you know, everything feel so distant nowadays... How are the kids ?

<ins>**Xavier**</ins>: Fine, so can you do the review ? 

<ins>**Charles**</ins>: Do you just need an aprrove or ?

<ins>**Xavier**</ins>: A real one please. You told us you have some experience in Rust, and I would really like the feedback of someone more experimented on this as it is a critical part of our design.

<ins>**Charles**</ins>: You always underestimate your capacity Charles, I don't have your talents, I am more a people guy you know, `and I was expecting to hire people from the Rust blog posts I would have wrote to show off to the HRs and catch the lies`, but I would do it anyway, even if I think you already surpasse me. Send me the link !

<ins>**Xavier**</ins>: Here we go !


```rust

// Agents are permanently connected to this server
pub struct AgentServer {
    // DashMap is a concurrent hashmap
    connected_agents: Arc<DashMap<AgentId, AgentSubscriberContext>>,
    agent_requests: DashMap<Uuid, AgentRequestContext>, 
}

#[async_trait]
impl AgentServer {

type AgentRequestSubscribeStream = Pin<Box<dyn Stream<Item = Result<AgentRequest, Status>> + Send>>;

// This method is called when an agent want to connect to our reverse proxy in order to receive requests.
// The agent call this endpoint and wait/listene that we forward us some requests
// It is equivalent of a subscribe in a pub/sub system
#[instrument(level="info", skip_all, fields(agent = %request.get_ref().agent_id))]
async fn agent_request_subscribe(&self, request: Request<SubscriberInfo>,) -> Result<Response<Self::AgentRequestSubscribeStream>, Status> {

    info!("agent connected");
    let (subscriber_ctx, agent_request_rx) = AgentSubscriberContext::new(request.into_inner())?;
    let agent_id = subscriber_ctx.id;

    let on_disconnected = {
        let connected_agents_weak_ref = Arc::downgrade(&self.connected_agents);
        // WARNING: ATM, the latest connected agent will receive events. Only 1 agent is supported so far
        self.connected_agents.insert(agent_id.clone(), subscriber_ctx);
        let span = Span::current();

        move || {
            let span = span.enter();
            debug!("agent disconnected");
            if let Some(agent_peer_map) = connected_agents_weak_ref.upgrade() {
                agent_peer_map.remove(&agent_id)
            }
        }
    };

    // Adapter to convert our channel that receive agent request from clients into a stream
    // when dropped, the on_disconnected() function is executed
    let stream = ChannelReceiverStream::new(agent_request_rx, on_disconnected)
                  .instrument(Span::current());

    Ok(Response::new(Box::pin(stream)))
}

// This endpoint is called by clients that need to send request to some specific agent.
// the request contains the information regarding which agent to contact.
// 1. We retrieve the context of the subscribed the agent (if any) from the global state and forward it (with a channel) the request.
// 2. We register the context of our request, within an global state for the agent response to be able to foarward us back via a channel the response stream
// 3. We wait some time for the agent to respond us or we timeout the client request
// 4. We return the agent response stream to our client response stream
#[instrument(level="info", skip_all, fields(request_id = %request.get_ref().id, call = field::Empty))]
async fn agent_request_publish(&self, request: Request<AgentRequest>,) -> Result<Response<Self::AgentRequestPublishStream>, Status> {

    let mut request = request.into_inner();
    let request_id = request.id;
    let agent_id = request.agent_id;

    // Retrieve the context of the concerned agent to be able to forward the request
    let subscriber_ctx = match self.connected_agents.get(&agent_id) {
        Some(ctx) => Ok(ctx),
        None => Err(Status::not_found("No agent subscribed for this id")),
    }?;

    // Now that we know that there is a subscribed agent, build the context for this request
    let (agent_ctx, mut client_ctx) = AgentRequestContext::new(request_id, &request);
    Span::current().record("call", agent_ctx.request_type.to_str());

    // Register the request for the agent to be able to retrieve it
    self.agent_requests.insert(request_id, agent_ctx);

    // Forward the request to the subscribed agent
    match subscriber_ctx.agent_request_tx.send(request).await {
      Ok(_) => {},
      Err(_) => {
            // don't leak the request if the agent does not respond
            self.agent_requests.remove(&request_id);
            return Err(Status::cancelled("agent disconnected"));
      }

    }

    // wait for the agent to respond with the stream of response we need
    let response_stream = match timeout(TIMEOUT_FIRST_MESSAGE, client_ctx.response_stream_rx.recv()).await {
        Ok(Some(response_stream)) => response_stream,
        _ => {
            self.agent_requests.remove(&request_id);
            return Err(Status::deadline_exceeded("Deadline exceeded for receiving the first message"));
        }
    };

    Ok(Response::new(Box::pin(response_stream)))
}

// This endpoint is used by the agent after receiving (from agent_request_subscribe) a request for returning the response of this request.
// After handling the request the agent call this endpoint with request-id in the headers and the response stream is the body.
// 1. The endpoint retrieve the context of the request (with the id) 
// 2. Forward the response stream to the client requesting it via the context channel
#[instrument(level = "info", skip_all, fields(request_id = field::Empty))]
async fn agent_response_publish(
    &self,
    request: Request<Streaming<AgentResponse>>,
) -> Result<Response<Empty>, Status> {
    let request_id = request
        .extensions()
        .get::<RequestId>()
        .ok_or(Status::unauthenticated("Missing request id"))?;
    Span::current().record("request_id", request_id.0.to_string());
    let request_id = request_id.0;

    // Retrieve the context for this agent request
    // We don't remove it from the hashmap because it is the client who has this responsibility
    // this allow to agent to retry the request if needed
    let request_ctx = match self.agent_requests.get(&request_id) {
        Some(ctx) => ctx,
        None => return Err(Status::not_found("Request Id not found")),
    };

    let (agent_response_stream, termination_rx) = StreamingAgentResponse::new(request.into_inner());
    let ret = request_ctx.response_stream_tx.try_send(agent_response_stream).await;
    match ret {
        Ok(_) => {
            termination_rx.await;
            Ok(Response::new(Empty {}))
        }
        Err(_) => {
            Err(Status::cancelled(""))
        }
    }
}
```

*Look nice, he use instrument in order to get proper logging, every hashmap are cleaned from their data so no mem leak anything in a global state, he even use a weak reference of his Arc to do it, he put some thought in it*

<ins>**Charles**</ins>: Xavier, I approved your PR. Nice job 👍, ship it !

How many issues can you spot in this code ?
If you would test it locally or under low load, most likely it will work, well most of the time !

## Issue #1: Order between futures are not guaranteed

Soon after releasing the agent server in preprod and testing it, Xavier found out that some agent stop responding after a while for unknown reason.
Not all agent stop responding just some and never the same after restarting the server. Doing some request on them works but after a while they just stop.
Xavier decides to send a request every minute to each agent, and soon after find one that stop responding.
Looking at the log for this agent, Xavier got.

```
...
agent_request_subscribe{agent_id=42} agent connected
agent_request_subscribe{agent_id=42} agent disconnected
agent_request_publish{request_id=66672} No agent subscribed for this id
```

Hum so the agent disconnected ? Stange ... Looking at the log of the agent shows nothing beside that it disconnected indeed, but reconnected just after the connection disruption. The agent seems alive and still connected to the gateway 🤔 What is happening ?

Xavier takes a look at the machine running the gateway and by running `ss -ntp` to show live connections, can clearly see the agent is still connected to the gtw.
```
State             Recv-Q             Send-Q                                  Local Address:Port                                   Peer Address:Port              Process
ESTAB             0                  0                                [::ffff:10.0.67.213]:8081                           [::ffff:ip.my.alive.agent]:55346              users:(("gateway",pid=8,fd=174))
```

So the only possible issue for the gateway to return `No agent subscribed for this id` while the agent is connected, is that there is an issue in the code and that the agent is not correctly registred 🤔

```rust
async fn agent_request_subscribe(&self, request: Request<SubscriberInfo>,) -> Result<Response<Self::AgentRequestSubscribeStream>, Status> {

    info!("agent connected");
    let (subscriber_ctx, agent_request_rx) = AgentSubscriberContext::new(request.into_inner())?;
    let agent_id = subscriber_ctx.id;

    let on_disconnected = {
        let connected_agents_weak_ref = Arc::downgrade(&self.connected_agents);
        // WARNING: ATM, the latest connected agent will receive events. Only 1 agent is supported so far
        self.connected_agents.insert(agent_id.clone(), subscriber_ctx);
        let span = Span::current();

        move || {
            let span = span.enter();
            debug!("agent disconnected");
            if let Some(agents_peer_map) = connected_agents_weak_ref.upgrade() {
                agents_peer_map.remove(&agent_id);
            }
        }
    };

    // Adapter to convert our channel that receive agent request from clients into a stream
    // when dropped, the on_disconnected() function is executed
    let stream = ChannelReceiverStream::new(agent_request_rx, on_disconnected)
                  .instrument(Span::current());

    Ok(Response::new(Box::pin(stream)))
}
```

From the logs everything happens in the `agent_request_subscribe` function so let's take a closer look at it.
What does this code do ? 

When an agent connect, it calls this functions in order to subscribe to a stream of events for him.
The only thing that this function is doing is
1. Creating a context of the agent containing a channel to forward the request
2. Insert/Replace the agent's context into the global map of connected agents
3. Put in place a hook/drop in order to remove the context agent from the global map

When we read this code, it seems very linear in what it does but in fact it is not.
The proximity in the lines makes thing easy to miss that some lines may not execute in the same order that we read it.

In our case, it is the on_disconnected function that is called in the Drop implementation.
```rust
        move || {
            let span = span.enter();
            debug!("agent disconnected");
            if let Some(agents_peer_map) = connected_agents_weak_ref.upgrade() {
                agents_peer_map.remove(&agent_id);
            }
        }
```

When a client re-connect, in a new context/task/future nothing guarantee that Drop of the previous context/task/future has been called.
Each task are independent and unless something synchronize them we can't rely for things to happen in some specific order.

Here what is happening, is:
1. the agent get disconnect for some reason, and reconnect itself to the gateway
2. By reconnecting the agent insert his context into the global map
3. The server got notified that the previous connection of the agent is broken, and thus drop the previous stream
4. Our on_disconnected got called when the previous stream is dropped, and remove the context of the agent from the global map
5. Sadly, the code remove the context of the newly connected agent
6. The agent is now unreachable from client point of view as we can't retrieve the agent's context anymore 💣

What is the fix ? 
Introduce a way to recognize if the context we remove was our own from our task.

```rust
    // subscriber_ctx.connect_at = Instant::now();

    let on_disconnected = {
        let connected_agents_weak_ref = Arc::downgrade(&self.connected_agents);
        let connected_at = subscriber_ctx.connected_at;
        // WARNING: ATM, the latest connected agent will receive events. Only 1 agent is supported so far
        self.connected_agents.insert(agent_id.clone(), subscriber_ctx);
        let span = Span::current();

        move || {
            let span = span.enter();
            debug!("agent disconnected");
            if let Some(agents_peer_map) = connected_agents_weak_ref.upgrade() {
                agents_peer_map.remove_if(&agent_id, |_, ctx| ctx.connected_at == connected_at);
            }
        }
    };
```

Xavier found a fix, he adds the point in time were our context was created and check before removing the context from the map if the connected time match.
After releasing the fix, the problem with agents unreachable disappared.


## Issue #2: 
Do not keep mutex across await points

## Issue #3: 
Await point are suspension, nothing guarantee your future will be resumed/cross an await point

## Issue #4: 
no guarantee of time across await

+++
title = "Debugging Rust application inside linux container"
description = "Learn how to debug backend Rust application within a container thanks to LLDB"
date = 2021-05-19
[extra]
header = '''<iframe class="hcenter" src="https://open.spotify.com/embed/track/3td69vL9Py7Ai9wfXYnvji" width="300" height="380" frameborder="0" allowtransparency="true" allow="encrypted-media"></iframe>'''
tags = ["rust", "lldb", "debugger", "container", "kubernetes", "memory"]
+++



I haven't found a lot of information around explaining how to use a debugger with rust.
Most posts seem outdated telling you that it is not there yet, while in practice it is usable.
We are far from what you can find in a JVM or JS ecosystem, but still if you are coming from C/C++ it is close
🤞

GDB (GNU Project Debugger) seems to be favored in some posts, while others are telling you to use lldb ¯\\\_(ツ)_/¯ .
For my part, I am using lldb as I am telling myself that if LLVM is the compilation backend for Rust, well, its debugger must be the most advanced one.

I still have questions regarding debugging with rust, this post aims to trigger discussion around this subject in order to let me grasp the full view, what my knowledge is missing. Of course, I am going to update the post. So please let me know :)


<ins>Pending questions</ins>:
  - How to cast raw pointer/address into rust type. Often got undeclared symbols or parsing errors ?

[Reddit discussion](https://www.reddit.com/r/rust/comments/nfkunr/debugging_rust_application_inside_linux_container/)

<br/>

# <ins>Let's start</ins>

So at some point in your life, `println()` or `error!()` will not be enough to save you. From some hazard in life, you accepted this job offer with some rust opportunities in it.
The rust part of the offer was not a lie, and you developed some applications that are running now in production.

The cake is good until your program hang :x

Your boss is calling you: Dave! We are losing multi-million dollars, hot babes and a customer is complaining ! Please fix that

- Okay boss, I am on it !

And now you are left wondering, how do I do that 🤔?
Your application is running on a remote server far from your local machine, it is not even running as a beautiful systemd service, but inside a container inside a kubernetes colossus. So there is little hope that you can attach your Clion or Vscode to it and add beautiful `eprintln()` to troubleshoot the issue.

<br/>

# <ins>The hammer</ins>

After some search on duckle-duckle-go, you found out that you can use some arcane debugger, used in the old times, the ones previous to the JavaScript eara.
The tools is murmured to be GDB or LLDB, in this tale only the exploit of LLDB are going to be narrated.

So you start, you try to execute inside your container :
```bash
kubectl exec -ti my_beautiful_container /bin/sh
# or
docker exec -ti  my_beautiful_container /bin/sh
# or your container engine command to attach into your running container
```

You end-up inside your container
```bash
sh-5.1# lldb
sh: lldb command not found

sh-5.1# uname -a  
Debian xxx

sh-5.1# apt-get update && apt-get install lldb
....
lldb installed !
```
Now that you have lldb you need to attach your debugger to your running process/application
To do that you need to know the [pid](https://en.wikipedia.org/wiki/Process_identifier) of your process

```bash
sh-5.1# ps aux | grep -i backend
# or
sh-5.1# pidof backend
6
```

Let's attach to it :O

```bash
sh-5.1# lldb -p 6
Process 6 stopped
Process 274403 stopped
* thread #1, name = 'backend', stop reason = signal SIGSTOP
    frame #0: 0x00007ffff7c1039e libc.so.6`epoll_wait + 94
libc.so.6`epoll_wait:
->  0x7ffff7c1039e <+94>:  cmpq   $-0x1000, %rax            ; imm = 0xF000
    0x7ffff7c103a4 <+100>: ja     0x7ffff7c103d8            ; <+152>
    0x7ffff7c103a6 <+102>: movl   %r8d, %edi
    0x7ffff7c103a9 <+105>: movl   %eax, 0xc(%rsp)
```

<ins>Warning</ins>: When you attach a debugger to a running process, it is stopping its execution/freezing it.
Meaning that when you do that, your application will not be able to serve traffic anymore until resumed
To resume your application type `c` or `continue` inside lldb shell

Hum not very helpful, contemplating thread 1 the assembly of the syscall epoll_wait is not going to help you a lot
You decide to get an overview of your whole application with `thread list`

```bash
(lldb) thread list
Process 279581 stopped
* thread #1: tid = 279581, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'backend', stop reason = signal SIGSTOP
  thread #2: tid = 279592, 0x00007ffff7c0aa9d libc.so.6`syscall + 29, name = 'r2d2-worker-0'
  thread #3: tid = 279593, 0x00007ffff7c0aa9d libc.so.6`syscall + 29, name = 'r2d2-worker-1'
  thread #4: tid = 279594, 0x00007ffff7c0aa9d libc.so.6`syscall + 29, name = 'r2d2-worker-2'
  thread #5: tid = 279595, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-rt:worker'
  thread #6: tid = 279596, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-rt:worker'
  thread #7: tid = 279597, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-rt:worker'
  thread #8: tid = 279598, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-rt:worker'
  thread #9: tid = 279599, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-rt:worker'
  thread #10: tid = 279600, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-rt:worker'
  thread #11: tid = 279601, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-rt:worker'
  thread #12: tid = 279602, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-rt:worker'
  thread #13: tid = 279603, 0x00007ffff7c1039e libc.so.6`epoll_wait + 94, name = 'actix-server ac'
```

Humm the application seems to be doing nothing, just waiting on some file descriptors due to the `epoll_wait`
Well, while you are here you try to dig further on threads stack trace to see it clear.

The command `bt` allow you to get the full stack trace while `thread select x` let you chose the thread you want to focus on.

```bash
(lldb) thread select 2
* thread #2, name = 'r2d2-worker-0'
    frame #0: 0x00007ffff7c0aa9d libc.so.6`syscall + 29
libc.so.6`syscall:
->  0x7ffff7c0aa9d <+29>: cmpq   $-0xfff, %rax             ; imm = 0xF001
    0x7ffff7c0aaa3 <+35>: jae    0x7ffff7c0aaa6            ; <+38>
    0x7ffff7c0aaa5 <+37>: retq
    0x7ffff7c0aaa6 <+38>: movq   0xc73a3(%rip), %rcx
(lldb) bt
* thread #2, name = 'r2d2-worker-0'
  * frame #0: 0x00007ffff7c0aa9d libc.so.6`syscall + 29
    frame #1: 0x00005555557e0f4c backend`parking_lot::condvar::Condvar::wait_until_internal::h6a12a91bfdfee605 + 780
    frame #2: 0x000055555568c673 backend`scheduled_thread_pool::Worker::run::hd2971d3a3d3f9b79 + 243
    frame #3: 0x000055555568e244 backend`std::sys_common::backtrace::__rust_begin_short_backtrace::h2cd3adeae9e017f9 + 20
    frame #4: 0x000055555568debf backend`core::ops::function::FnOnce::call_once$u7b$$u7b$vtable.shim$u7d$$u7d$::h215295889fafda4c + 111
    frame #5: 0x000055555586e5ea backend`std::sys::unix::thread::Thread::new::thread_start::hb95464447f61f48d [inlined] _$LT$alloc..boxed..Box$LT$F$C$A$GT$$u20$as$u20$core..ops..function..FnOnce$LT$Args$GT$$GT$::call_once::hc444a77f8dd8d825 at boxed.rs:1546:9
    frame #6: 0x000055555586e5e4 backend`std::sys::unix::thread::Thread::new::thread_start::hb95464447f61f48d [inlined] _$LT$alloc..boxed..Box$LT$F$C$A$GT$$u20$as$u20$core..ops..function..FnOnce$LT$Args$GT$$GT$::call_once::h8b68a0a9a2093dfc at boxed.rs:1546
    frame #7: 0x000055555586e5db backend`std::sys::unix::thread::Thread::new::thread_start::hb95464447f61f48d at thread.rs:71
    frame #8: 0x00007ffff7e33299 libpthread.so.0`start_thread + 233
    frame #9: 0x00007ffff7c10053 libc.so.6`__clone + 67
```

Hehe nice you can see the guts of the libs you are using. As you boss is already aware of the incident, you take your time and wander around.

`frame x` let you select a particular frame in the stack trace

```bash
(lldb) f 2
frame #2: 0x000055555568c673 backend`scheduled_thread_pool::Worker::run::hd2971d3a3d3f9b79 + 243
backend`scheduled_thread_pool::Worker::run::hd2971d3a3d3f9b79:
->  0x55555568c673 <+243>: jmp    0x55555568c5e0            ; <+96>
    0x55555568c678 <+248>: nopl   (%rax,%rax)
    0x55555568c680 <+256>: cmpb   $0x0, 0x30(%r15)
    0x55555568c685 <+261>: jne    0x55555568c7a7            ; <+551>
(lldb) f 3
frame #3: 0x000055555568e244 backend`std::sys_common::backtrace::__rust_begin_short_backtrace::h2cd3adeae9e017f9 + 20
backend`std::sys_common::backtrace::__rust_begin_short_backtrace::h2cd3adeae9e017f9:
->  0x55555568e244 <+20>: movq   0x8(%rsp), %rax
    0x55555568e249 <+25>: lock
    0x55555568e24a <+26>: subq   $0x1, (%rax)
    0x55555568e24e <+30>: jne    0x55555568e25a            ; <+42>
```

erf, gibrish again. Dude what have you done wrong in your life :x

<br/>

# <ins>Revelation of symbols</ins>

After hours of duckle-duckle-go search, you found out that debugging information are stored inside binaries thanks to [DWARF symbols](https://en.wikipedia.org/wiki/DWARF).
By default, when you compile your application with `cargo build --release`, the compiler is not going to emit those debugging symbols inside your final binary to save you space.

<ins>Note</ins>: By default, Cargo does not remove all symbols of release build's binary, it keeps a minimum vital of them. If you want to remove them completely use `strip` on your final artifact

You can see it by looking at the symbol table inside you binary

```bash
> nm target/release/backend
...
0000000000131fe0 T _ZN9humantime4date21format_rfc3339_micros17h91fde5c22c042977E
0000000000131fd0 T _ZN9humantime4date21format_rfc3339_millis17h203b8b50314b3e04E
0000000000131fc0 T _ZN9humantime4date22format_rfc3339_seconds17hb7a5e93382ced9abE
0000000000131af0 t _ZN9termcolor11ColorChoice20should_attempt_color17h2d428f8a12105313E
0000000000131c60 T _ZN9termcolor12BufferWriter5print17h8d54c30d302b8181E
0000000000131c30 T _ZN9termcolor12BufferWriter6buffer17h0e9d2e139728bbd3E
0000000000131bf0 T _ZN9termcolor12BufferWriter6stderr17h7d5b8e50f9ce6b9aE
0000000000131bb0 T _ZN9termcolor12BufferWriter6stdout17h6c6ef5a9fb5d6effE
0000000000130e40 t _ZN9termcolor13Ansi$LT$W$GT$11write_color17h2170d9aadd045621E
0000000000131dd0 T _ZN9termcolor6Buffer5clear17he147cb392538bfdeE
0000000000131de0 T _ZN9termcolor6Buffer8as_slice17hdfcf6986db042facE
0000000000131e30 T _ZN9termcolor9ColorSpec11set_intense17ha85d3b8f61d3604fE
0000000000131df0 T _ZN9termcolor9ColorSpec3new17h2985cbe1e097415eE
0000000000131e10 T _ZN9termcolor9ColorSpec6set_fg17he5e0a178791f9adaE
0000000000131e20 T _ZN9termcolor9ColorSpec8set_bold17h2d0333c4d5151a37E
```

You can even find *luckily* the functions of your code inside it
```bash
> nm target/release/backend | grep backend
000000000008b5c0 T _ZN4core3ptr89drop_in_place$LT$actix_web..service..ServiceFactoryWrapper$LT$backend..get_videos$GT$$GT$17h63b989ad30dd3298E.llvm.15681288489354736176
000000000008b5c0 T _ZN4core3ptr91drop_in_place$LT$actix_web..service..ServiceFactoryWrapper$LT$backend..insert_video$GT$$GT$17h87da2b27af8a9354E.llvm.15681288489354736176
0000000000090990 t _ZN4core3ptr92drop_in_place$LT$backend..main..$u7b$$u7b$closure$u7d$$u7d$..$u7b$$u7b$closure$u7d$$u7d$$GT$17ha69044c956c3012fE
000000000009a4e0 t _ZN4core3ptr92drop_in_place$LT$backend..main..$u7b$$u7b$closure$u7d$$u7d$..$u7b$$u7b$closure$u7d$$u7d$$GT$17ha69044c956c3012fE
00000000000c9050 t _ZN4core3ptr92drop_in_place$LT$backend..main..$u7b$$u7b$closure$u7d$$u7d$..$u7b$$u7b$closure$u7d$$u7d$$GT$17ha69044c956c3012fE.llvm.1852688250768946083
0000000000093dc0 t _ZN78_$LT$backend..get_videos$u20$as$u20$actix_web..service..HttpServiceFactory$GT$8register17h3241141003c625feE
0000000000093fd0 t _ZN80_$LT$backend..insert_video$u20$as$u20$actix_web..service..HttpServiceFactory$GT$8register17h914f6b153d5e7c20E
00000000000941e0 t _ZN82_$LT$backend..add_video_tags$u20$as$u20$actix_web..service..HttpServiceFactory$GT$8register17he676cb44c0a4135cE
```

If you care to know why all function names have a strange naming, it is due to [name mangling](https://en.wikipedia.org/wiki/Name_mangling). It is a convention identify uniquely functions across your whole application and librairies even if mutliple have the same name


By playing with `nm` you clearly see that your debug build have way more symbols than your release build
```bash
> nm target/release/backend | wc -l
23751
> nm target/debug/backend | wc -l
53912
```

How to get them for your release application 🤞?

Cargo allows you to embed debug symbols even in release builds by using profile.

In your `Cargo.toml` simply add a section
```toml
[profile.release]
debug = true
```


Now rebuild your application
```bash
❯ cargo build --release
...
    Finished release [optimized + debuginfo] target(s) in 0.06s
```
Congrats !!! As now you can see you have produced an `optimized + debuginfo` binary

Sadly if you now look at the size of your binary, it has exploded
```bash
# Before debug = true
❯ la target/release/backend
Permissions Size User  Date Modified Name
.rwxr-xr-x   11M erebe 17 May 20:19  target/release/backend

# After
❯ la target/release/backend
Permissions Size User  Date Modified Name
.rwxr-xr-x  113M erebe 17 May 23:00  target/release/backend
```

An x10 growth, not good :x

If you want to mitigate this you can also enable [LTO](https://llvm.org/docs/LinkTimeOptimization.html), without entering too much into details, at the expanse of more CPU during the linking phase (build) of your binary, unused function are going to be trimmed out of your binary.

```toml
[profile.release]
debug = true
lto = true
```
```bash
❯ cargo build --release
...
    Finished release [optimized + debuginfo] target(s) in 2m 19s

❯ la target/release/backend
Permissions Size User  Date Modified Name
.rwxr-xr-x   52M erebe 17 May 23:10  target/release/backend
```

Half the size 🙏!


<ins>Note</ins>: Running application with debug symbols will not arm the performance, maybe 1% or 2% will be lost.
But between undebuggable applications and a tiny loss of performance the choice is already made for me.
If you are running a huge fleet you may have the luxury to have canaries applications
Also, whatever the final binary disk size is, the Linux kernel is smart enough to no load symbols when we are not needed.
So even if you end-up 1GB of binary size, you will be fine

<br/>

# <ins>Security is a pain</ins>

By now your coffee is cold, and you finish it in one sip afer having published a new container image of your application with debug symbols in it \o/

Your phone ring: Hello Dave ! Chief Security Officer here, from the desk next to you, I *cough* my eBPF probes saw that you were running as root inside your container just before...
It is a bad security practice...  Please run your application as a normal user... You are not special Dave... Drop capabilities... Live simply...

You go make another coffee...
Once back you made your image run as a normal user, published it and deployed it in production.
Now is the time to get another look at it

```bash
kubectl exec -ti my_beautiful_container /bin/sh
sh-5.1# apt-get update && apt-get install lldb
failed: Operation not permitted
```

Well :x How do I attach to my application if I don't have a debugger ?
Let's me the sudo of the container world. The yaml file below is going to
spawn a container on each node of your kubernetes cluster with all security disabled and mounting the / of the node inside the container.
Basically those containers will be running as kind of the hill

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: debug
spec:
  selector:
    matchLabels:
      app: debug
  template:
    metadata:
      labels:
        app: debug
      name: debug
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: linux
        image: ubuntu:latest
        imagePullPolicy: Always
        args:
        - sleep
        - "604800"
        securityContext:
          privileged: true
          runAsGroup: 0
          runAsUser: 0
        volumeMounts:
        - mountPath: /mnt/host
          name: host
      volumes:
      - hostPath:
          path: /
        name: host
```
```bash
kubectl apply -f debugger.yaml
```

<ins>Note</ins>: Don't do that if you have a cluster with hundreds of nodes. Use a selector to target specific node were your app is running

Now that your sudo containers are starting, take time to consider progress. How today to start a program as root we need to download hundred of megabytes in a distributed fashion, gaze above the complexity to do that...

Ha it is ready, this fiber was worth the cost.
Simply find the node were one of the application is running on and exec into your daemon/sudo container on it
```bash
kubectl exec -ti debug-xxxx
# apt-get update && apt-install lldb
lldb installed !!!

# lldb -p $(pidof backend)
lldb) process attach --pid 22780
error: attach failed: lost connection
```

Wait what Oo

Even with our sudo container you can't attach to the process !
Due to how [namespaces](https://en.wikipedia.org/wiki/Linux_namespaces) isolation works in Linux, you first need to enter/inject yourself inside the namespaces of your container.
For that you can use the [nsenter](https://www.redhat.com/sysadmin/container-namespaces-nsenter) tool (for namespace enter)

P.S: GDB is less picky here, it will let you attach to the process and debugg it with only a warning telling you pid/thread id will be wrong

```bash
# First we retrieve the PID of of our application from the root namespace perspective
sh-5.1# pidof backend
22780
# Now we retrieve PID of our application but viewed from within the namespace
sh-5.1# nsenter -t 22780 -p -r pidof backend
6 # ha like before :wink
nsenter -t 22780 -p -n -i -u -C -- lldb -p 6
(lldb) # Hourra
```

<ins>Note</ins>: Installing lldb within the container may be advisable. It would simplify the nsenter command `nsenter -t 22780 -a -- lldb -p 6` and allow to troubleshoot more easily at first

<ins>Note2</ins>: GDB is less picky than lldb here. You can attach to your process if you are running from a different namespace. Only at a cost of a warning 
`warning: Target and debugger are in different PID namespaces; thread lists and other data are likely unreliable.  Connect to gdbserver inside the container.`

<br/>

# Grand Final

You can now see that you have a lot more depth when you display stack trace :)

```bash
(lldb) bt
* thread #1, name = 'backend', stop reason = signal SIGSTOP
    frame #0: 0x00007ffff7c0d39e libc.so.6`epoll_wait + 94
    frame #1: 0x000055555575515f backend`mio::sys::unix::epoll::Selector::select::heff706d7852ffc6e(self=<unavailable>, evts=0x00007fffffffcf38, awakener=(__0 = <extracting data from value failed>), timeout=<unavailable>) at epoll.rs:72:27
    frame #2: 0x0000555555753fcf backend`mio::poll::Poll::poll::hfcdad969794d946c at poll.rs:1178:23
    frame #3: 0x0000555555753f78 backend`mio::poll::Poll::poll::hfcdad969794d946c at poll.rs:1139
    frame #4: 0x0000555555753ca6 backend`mio::poll::Poll::poll::hfcdad969794d946c(self=0x000055555596ca50, events=0x00007fffffffcf38, timeout=<unavailable>) at poll.rs:1010
    frame #5: 0x000055555581333f backend`tokio::io::driver::Driver::turn::hb33d498584f14e3a(self=0x00007fffffffcf38, max_wait=<unavailable>) at mod.rs:107:15
    frame #6: 0x00005555556743b7 backend`_$LT$tokio..park..either..Either$LT$A$C$B$GT$$u20$as$u20$tokio..park..Park$GT$::park::hdbf9056971426175 [inlined] _$LT$tokio..time..driver..Driver$LT$T$GT$$u20$as$u20$tokio..park..Park$GT$::park::hada80dd7e5f58d62(self=0x00007fffffffcf08) at mod.rs:0
    frame #7: 0x0000555555674368 backend`_$LT$tokio..park..either..Either$LT$A$C$B$GT$$u20$as$u20$tokio..park..Park$GT$::park::hdbf9056971426175(self=0x00007fffffffcf00) at either.rs:28
  * frame #8: 0x00005555555d7730 backend`backend::main::h33b6aeb7ca1e48a2 at basic_scheduler.rs:158:29
    frame #9: 0x00005555555d7430 backend`backend::main::h33b6aeb7ca1e48a2 [inlined] tokio::runtime::basic_scheduler::enter::_$u7b$$u7b$closure$u7d$$u7d$::h8592649e659d07b4 at basic_scheduler.rs:213
    frame #10: 0x00005555555d7422 backend`backend::main::h33b6aeb7ca1e48a2 at scoped_tls.rs:63
    frame #11: 0x00005555555d73dc backend`backend::main::h33b6aeb7ca1e48a2 at basic_scheduler.rs:213
    frame #12: 0x00005555555d73dc backend`backend::main::h33b6aeb7ca1e48a2 [inlined] tokio::runtime::basic_scheduler::BasicScheduler$LT$P$GT$::block_on::h9c786dedfc6a5aa6(self=<unavailable>) at basic_scheduler.rs:123
    frame #13: 0x00005555555d73dc backend`backend::main::h33b6aeb7ca1e48a2 at mod.rs:444
    frame #14: 0x00005555555d7187 backend`backend::main::h33b6aeb7ca1e48a2 at context.rs:72
    frame #15: 0x00005555555d717c backend`backend::main::h33b6aeb7ca1e48a2 [inlined] tokio::runtime::handle::Handle::enter::he939f40f7d689244(self=<unavailable>, f=closure-0 @ 0x0000563da12bba80) at handle.rs:76
    frame #16: 0x00005555555d703a backend`backend::main::h33b6aeb7ca1e48a2 at mod.rs:441
    frame #17: 0x00005555555d703a backend`backend::main::h33b6aeb7ca1e48a2 [inlined] tokio::task::local::LocalSet::block_on::hc8de46bea7c62d2d(self=0x00007fffffffce78, rt=<unavailable>) at local.rs:353
    frame #18: 0x00005555555d703a backend`backend::main::h33b6aeb7ca1e48a2 [inlined] actix_rt::runtime::Runtime::block_on::h9e2e8a1149ae6d56(self=0x00007fffffffce78) at runtime.rs:89
    frame #19: 0x00005555555d703a backend`backend::main::h33b6aeb7ca1e48a2 [inlined] actix_rt::builder::SystemRunner::block_on::h9e96257a2d917034(self=0x00007fffffffce78, fut=(__0 = backend::main::generator-0 @ 0x00007fffffffd7b8)) at builder.rs:187
    frame #20: 0x00005555555d6dc1 backend`backend::main::h33b6aeb7ca1e48a2 at main.rs:73
    frame #21: 0x00005555556e84e3 backend`std::sys_common::backtrace::__rust_begin_short_backtrace::h49234270be9c7bdc [inlined] core::ops::function::FnOnce::call_once::h227b7deeec412b68((null)=<unavailable>) at function.rs:227:5
    frame #22: 0x00005555556e84e1 backend`std::sys_common::backtrace::__rust_begin_short_backtrace::h49234270be9c7bdc(f=<unavailable>) at backtrace.rs:125
    frame #23: 0x00005555556e83ff backend`std::rt::lang_start::_$u7b$$u7b$closure$u7d$$u7d$::hcb9052462902a6a2 at rt.rs:66:18
    frame #24: 0x00005555555d8507 backend`main + 791
    frame #25: 0x00007ffff7b35b25 libc.so.6`__libc_start_main + 213
    frame #26: 0x00005555555c318e backend`_start + 46
```

You can display variables of a specific frame thanks to `var`
```bash
(lldb) f 8
frame #8: 0x00005555555d7730 backend`backend::main::h33b6aeb7ca1e48a2 at basic_scheduler.rs:158:29
   155                          Some(task) => crate::coop::budget(|| task.run()),
   156                          None => {
   157                              // Park until the thread is signaled
-> 158                              scheduler.park.park().ok().expect("failed to park");
   159
   160                              // Try polling the `block_on` future next
   161                              continue 'outer;
```
```bash
(lldb) var # display variable of the focused stack frame
(tokio::runtime::basic_scheduler::BasicScheduler<tokio::park::either::Either<tokio::time::driver::Driver<tokio::park::either::Either<tokio::io::driver::Driver, tokio::park::thread::ParkThread>>, tokio::park::either::Either<tokio::io::driver::Driver, tokio::park::thread::ParkThread>> > *) scheduler = 0x00007fffffffcec8
(tokio::runtime::basic_scheduler::Context *) context = 0x00007fffffffc5f8
(core::future::from_generator::GenFuture<tokio::task::local::{{impl}}::run_until::generator-0>) future = {
  __0 = {
    __0 = 0x00007fffffffce78
    __1 = (__0 = backend::main::generator-0 @ 0x00007fffffffcfd0)
  }
}
(tokio::runtime::enter::Enter) _enter = (_p = core::marker::PhantomData<core::cell::RefCell<void> > @ 0x00007fffffffc560)
(tokio::util::wake::WakerRef) waker = {
  waker = {
    value = {
      waker = {
        data = 0x0000555555971510
        vtable = 0x0000555555927438
      }
    }
  }
  _p = {}
}
(core::task::wake::Context) cx = {
  waker = 0x00007fffffffc660
  _marker = {}
}
(core::future::from_generator::GenFuture<tokio::task::local::{{impl}}::run_until::generator-0>) future = {
  __0 = {
    __0 = 0x00007fffffffce78
    __1 = (__0 = backend::main::generator-0 @ 0x00007fffffffca88)
  }
}
(core::pin::Pin<core::future::from_generator::GenFuture<tokio::task::local::{{impl}}::run_until::generator-0> *>) future = {
  pointer = 0x00007fffffffca80
}
(core::ops::range::Range<unsigned long>) iter = <no location, value may have been optimized out>
(unsigned long) __next = <no location, value may have been optimized out>
(unsigned char) tick = <variable not available>
(core::option::Option<tokio::runtime::task::Notified<alloc::sync::Arc<tokio::runtime::basic_scheduler::Shared>>>) next = {}
```


<ins>Note:</ins> When the frame don't have enough variable (< 3), llvm does not include DWARF symbol so you will not be able to get information for them

To display variable you can use `print`
```bash
(lldb) p waker.waker.value.waker
(core::task::wake::RawWaker) $12 = {
  data = 0x0000555555971510
  vtable = 0x0000555555927438
}
```

What are those [vtable](https://en.wikipedia.org/wiki/Virtual_method_table) ?
It is a way to implement polymorphism/virtual dispatch for trait in rust. If you have made some C++ it should be not new to you as it is often an interview question to explain [virtual table](https://en.wikipedia.org/wiki/Virtual_method_table)

```bash
# Notice the * in front of waker, to deference the pointer
(lldb) p *waker.waker.value.waker.vtable
(core::task::wake::RawWakerVTable) $14 = {
  clone = 0x000055555567adc0 (backend`tokio::util::wake::clone_arc_raw::hb0fa91ccdcab6440 [inlined] core::sync::atomic::atomic_add::h5cd43bb8297907fc at atomic.rs:1735
backend`tokio::util::wake::clone_arc_raw::hb0fa91ccdcab6440 [inlined] core::sync::atomic::AtomicUsize::fetch_add::h85326e4080a93b94 at sync.rs:1279
backend`tokio::util::wake::clone_arc_raw::hb0fa91ccdcab6440 [inlined] _$LT$alloc..sync..Arc$LT$T$GT$$u20$as$u20$core..clone..Clone$GT$::clone::h9d545c835c3dd627 at manually_drop.rs:50
backend`tokio::util::wake::clone_arc_raw::hb0fa91ccdcab6440 [inlined] _$LT$core..mem..manually_drop..ManuallyDrop$LT$T$GT$$u20$as$u20$core..clone..Clone$GT$::clone::h5f7e249cdd8514a0 at wake.rs:57
backend`tokio::util::wake::clone_arc_raw::hb0fa91ccdcab6440 [inlined] tokio::util::wake::inc_ref_count::he6b5ec4f0529c58a at wake.rs:65
backend`tokio::util::wake::clone_arc_raw::hb0fa91ccdcab6440 at wake.rs:65)
  wake = 0x000055555567ade0 (backend`tokio::util::wake::wake_arc_raw::h77f20021318c61d4 [inlined] core::ptr::mut_ptr::_$LT$impl$u20$$BP$mut$u20$T$GT$::offset::h6da3001839666071 at sync.rs:849
backend`tokio::util::wake::wake_arc_raw::h77f20021318c61d4 [inlined] alloc::sync::Arc$LT$T$GT$::from_raw::h8f399ef41e6f9b5e at wake.rs:70
backend`tokio::util::wake::wake_arc_raw::h77f20021318c61d4 at wake.rs:70)
  wake_by_ref = 0x000055555567ae30 (backend`tokio::util::wake::wake_by_ref_arc_raw::hd4fc59d0c10ff679 [inlined] _$LT$alloc..boxed..Box$LT$dyn$u20$tokio..park..Unpark$GT$$u20$as$u20$tokio..park..Unpark$GT$::unpark::h94d0f37295bbd56d at basic_scheduler.rs:324
backend`tokio::util::wake::wake_by_ref_arc_raw::hd4fc59d0c10ff679 [inlined] _$LT$tokio..runtime..basic_scheduler..Shared$u20$as$u20$tokio..util..wake..Wake$GT$::wake_by_ref::haf1191c2b071f4f4 at wake.rs:78
backend`tokio::util::wake::wake_by_ref_arc_raw::hd4fc59d0c10ff679 at wake.rs:78)
  drop = 0x000055555567ae40 (backend`tokio::util::wake::drop_arc_raw::h658ddd69854eee7c at wake.rs:81)
}
```

Data pointer can be often a pain, if you try to print them, you will get nothing out. Because it has a type of `void*` or `u8*` the only information you have is that it is a pointer, without knowing the size of the object behind it in memory or anything :x
```bash
(lldb) p *waker.waker.value.waker.data
(lldb) var waker.waker.value.waker.data
(void *) waker.waker.value.waker.data = 0x0000555555971510
```

A handy command to explore the data anyway it to use `memory read` or `x`. It let you read an arbitrary memory section from a specific address.
```bash
(lldb) x -c 256 waker.waker.value.waker.data
0x555555971510: d0 14 97 55 55 55 00 00 00 d0 cd 96 55 55 55 00  ...UUU......UUU.
0x555555971520: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
0x555555971530: c0 10 97 55 55 55 00 00 80 00 00 00 00 00 00 00  ...UUU..........
0x555555971540: a0 10 97 55 55 55 00 00 48 83 96 55 55 55 00 00  ...UUU..H..UUU..
0x555555971550: 00 00 00 00 00 00 00 00 11 04 00 00 00 00 00 00  ................
0x555555971560: 10 1e 97 55 55 55 00 00 80 c4 96 55 55 55 00 00  ...UUU.....UUU..
0x555555971570: b0 52 99 55 55 55 00 00 30 53 99 55 55 55 00 00  .R.UUU..0S.UUU..
0x555555971580: c0 8e 99 55 55 55 00 00 00 00 00 00 00 00 00 00  ...UUU..........
```

In this case it is not helping much, but when you have some kind of bytestream (network payload, file data, ...) it is very useful to get the content of it.
If you know the type behind it, you can cast your raw memory into something more useful with `print`.

From above if you squint you can see that the data looks like 2 pointers.
By looking at the [code](https://docs.rs/tokio/1.6.0/src/tokio/util/wake.rs.html#33) you see that it is a waker type, so you cast...
```bash
(lldb) p *((core::task::wake::Waker*) waker.waker.value.waker.data)
(core::task::wake::Waker) $36 = {
  waker = {
    data = 0x00005555559714d0
    vtable = 0x0055555596cdd000
  }
}
```

Looks good, but is it correct ?
You don't know ¯\\\_(ツ)_/¯, that's the magic behind unchecked cast of raw memory, you can't tell for sure. Nobody is going to save you if you turn your bytes into a mad dog

You may want to look also into registers `register`, it can be useful when inspecting syscall as by conventions value are passed into registers
```bash
(lldb) f 0
frame #0: 0x00007ffff7c0d39e libc.so.6`epoll_wait + 94
libc.so.6`epoll_wait:
->  0x7ffff7c0d39e <+94>:  cmpq   $-0x1000, %rax            ; imm = 0xF000
    0x7ffff7c0d3a4 <+100>: ja     0x7ffff7c0d3d8            ; <+152>
    0x7ffff7c0d3a6 <+102>: movl   %r8d, %edi
    0x7ffff7c0d3a9 <+105>: movl   %eax, 0xc(%rsp)
(lldb) register read
General Purpose Registers:
       rax = 0xfffffffffffffffc
       rbx = 0x00007fffff7ff000
       rcx = 0x00007ffff7c0d39e  libc.so.6`epoll_wait + 94
       rdx = 0x0000000000000400
       rdi = 0x0000000000000003
       rsi = 0x0000555556160060
       rbp = 0x0000000000000000
       rsp = 0x00007fffffff8e60
        r8 = 0x0000000000000000
```

if you take a look at [linux syscall list](https://filippo.io/linux-syscall-table/) you can find out the convention for epoll_wait
```bash
%rdi          %rsi                           %rdx              %r10
int epfd    struct epoll_event* events    int maxevents    int timeout
```

So technically if you take the address from rsi and cast it to `struct epoll_event*` you should be able to get the info.
<ins>Help Wanted</ins>: In my case I only manage to make crash my lldb, or I am unable to cast the pointer
```bash
(lldb) p 0x0000000000000400 #rdx
(int) $0 = 1024 #max events
(lldb) p ((struct epoll_event*) 0x0000555556160060)
PLEASE submit a bug report to https://bugs.llvm.org/ and include the crash backtrace.
Stack dump:
0.      Program arguments: lldb target/debug/backend
1.      HandleCommand(command = "p ((struct epoll_event*) 0x0000555556160060)")

# While the address is correct and value retrievable
# let go back one frame

(lldb) f 1
frame #1: 0x000055555575515f backend`mio::sys::unix::epoll::Selector::select::heff706d7852ffc6e(self=<unavailable>, evts=0x00007fffffffcf38, awakener=(__0 = <extracting data from value failed>), timeout=<unavailable>) at epoll.rs:72:27
   69           // Wait for epoll events for at most timeout_ms milliseconds
   70           evts.clear();
   71           unsafe {
-> 72               let cnt = cvt(libc::epoll_wait(self.epfd,
   73                                              evts.events.as_mut_ptr(),
   74                                              evts.events.capacity() as i32,
   75                                              timeout_ms))?;
(lldb) var
(mio::sys::unix::epoll::Selector *) self = <no location, value may have been optimized out>

(mio::sys::unix::epoll::Events *) evts = 0x00007fffffffcf38
(mio::token::Token) awakener = (__0 = <extracting data from value failed>)
(core::option::Option<core::time::Duration>) timeout = <variable not available>
lldb) p evts->events
(alloc::vec::Vec<libc::unix::linux_like::epoll_event, alloc::alloc::Global>) $0 = {
  buf = {
    ptr = {
      pointer = 0x000055555596d060
      _marker = {}
    }
    cap = 1024 # we retrieve our max events
    alloc = {}
  }
  len = 0

(lldb) p evts->events.buf.ptr.pointer
(libc::unix::linux_like::epoll_event *) $1 = 0x0000555556160060
(lldb) p *evts->events.buf.ptr.pointer
(libc::unix::linux_like::epoll_event) $2 = (events = 1, u64 = 9223372036854775807)

# but whatever I do I can't manage to cast my raw pointer to the correct struct
(lldb) p (libc::unix::linux_like::epoll_event *) 0x000055555596d060
error: <user expression 24>:1:8: expected unqualified-id
```

Nothing really conclusive so far, so you try to put a breakpoint on well known function with `b`

<ins>Note</ins>: By default it is a regex breakpoint, meaning lldb is going to put a breakpoint on all the symbols that match the pattern. So don't use a short pattern, or you will end-up with a lot of breakpoints...

```bash
(lldb) b list_videos
Breakpoint 1: where = backend`_$LT$F$u20$as$u20$threadpool..FnBox$GT$::call_box::h915c50d68db449a2 + 216 [inlined] core::option::Option$LT$T$GT$::as_ref::hfd6c0b8b5291e7c7 at lib.rs:627, address = 0x00005555555c82d8
(lldb) continue # the program is unfreeze and start running again
```

And now you wait...

- Hey Dave, what are you doing ?
- Hi John, looking why my app does not seem to handle any traffic
- Nobody told you ?
- What ?
- Load balancers are down for a few hours in order to clean their NICs
- *sight*

<br/>

# Summary  
  - You need to have debug symbol in your release build (it will increase disk size of binary)
  - A good cheatsheet of lldb commands can be found [here](https://lldb.llvm.org/use/map.html)
  - You have a tiny ui inside lldb by typing `gui` inside the shell (warning: you shell will be broken after)
  - To debugger a container you need to spawn another container with security disabled and use `nsenter` to break linux namespaces 

[Reddit discussion](https://www.reddit.com/r/rust/comments/nfkunr/debugging_rust_application_inside_linux_container/)



<br/>
<br/>
<br/>

# Bonus Point: GDB Remote Server

The statement of the beginning was a bit of a lie, you can debug a remote process within your confy IDE (I.e: clion/vscode).
For that you only need to start a gdbserver on your remote machine with
```bash
$ gdbserver 0.0.0.0:1234 pid_program 
```

Be sure that the port/remote machine is accessible from your local machine.
If you are inside a kubernetes you can do a port-forward `kubectl port-forward` to reach your gdb server.

After that open your project in CLIO, go to configure -> Add new configuration -> GDB remote Debug, and enter the ip:port of your server

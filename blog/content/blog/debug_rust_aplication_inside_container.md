+++
title = "Debugging rust application inside linux container"
date = 2021-05-17
[extra]
header = '''<iframe src="https://open.spotify.com/embed/track/3td69vL9Py7Ai9wfXYnvji" width="300" height="380" frameborder="0" allowtransparency="true" allow="encrypted-media"></iframe>'''
+++



I haven't found a lot of information around explaining how to use a debugger with rust.
Most posts seem outdated telling you that it is not there yet, while in practice it is usable.
We are far from what you can find in a JVM or JS ecosystem, but still if you are coming from C/C++ it is close 
🤞

GDB (GNU Project Debugger) seems to be favored in some posts, while others are telling you to use lldb ¯\\\_(ツ)_/¯ .
For my part, I am using lldb as I am telling myself that if LLVM is the compilation backend for Rust, well, its debugger must be the most advanced one.

As I don't have any certainty on this topic of debugging with rust, this post aims to trigger discussion around this subject in order to let me grasp the full view, what my knowledge is missing. Of course, If I am going to learn new stuff, I am going to update the post. So please let me know :)


# <ins>Let's start</ins>

So at some point in your life, `println()` or `error!()` will not be enough to save you. From some hazard in life, you accepted this job offering with some rust opportunities in it.
The rust part of the offering was not a lie, and you developped some applications that are running now in production.

The cake is good until your program hang :x 

Your boss is calling you: Dave! We are losing multi-million dollars, hot babes and a customer is complaining ! Please fix that

- Okay boss, I am on it !

And now you are left wondering, how do I do that 🤔? Your application is running on a remote server far from your local machine, it is not even running as a beautiful systemd service, but inside a container inside a kubernetes colossus. So there is little hope that you can attach your Clion or Vscode to it and add beautiful `eprintln()` to troubleshoot the issue.


# <ins>The hammer</ins>

After some search on duckle-duckle-go, you found out that you can use some arcane debugger, used in the old times, the ones previous to the JavaScript eara.
The tools is murmured to be GDB or LLDB, in this tale only the exploit of LLDB are going to be brought narrated.

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

Hum not very helpful, contempling thread 1 the assembly of the syscall epoll_wait is not going to help you a lot
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

erf, gibrish again. Dude that you have done wrong in your life :x


# <ins>Revelation of symbols</ins>

After hours of duckle-duckle-go search, you found out that debugging informations are stored inside binaries thanks to [DWARF symbols](https://en.wikipedia.org/wiki/DWARF).
By default when you compile your application with `cargo build --release`, the compiler is not going to emit those debugging symbols inside your final binary to save you space.

<ins>Note</ins>: By default, Cargo does not remove all symbols of release build's binary, it keeps a minimum vital of them. If you want to remove them completly use `strip` on your final artifact

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
If you want to mitigate this you can also enable [LTO](https://llvm.org/docs/LinkTimeOptimization.html), without entering too much into details at the expensave of more CPU during the linking phase (build) of your binary, unused function are going to be trimmed out of your binary.

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
Also whatever the final binary disk size is, the Linux kernel is smart enough to no load symbols when we are not needed.
So even if you end-up 1GB of binary size, you will be fine


# <ins>Revelation: Security is a pain</ins>

By now your coffee is cold, and you finish it in one sip afer having published a new container image of your application with debug symbols in it \o/

Your phone ring: Hello Dave ! Chief Security Officer here, from the desk next to you, I *cough* my eBPF probes saw that you were running as root inside your container just before...
It is a bad security practice...  Please run your application as a normal user... You are not special Dave... Drop capabilities... Live simply...

You go make an other coffee...
Once back you made your image run as a normal user, published it and deployed it in production.
Now is the time to get an other look at it

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
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
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
          type: ""
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

```
sh-5.1# pidof backend # First we retrieve the PID of of our application from the root namespace perspective
22780
sh-5.1# nsenter -t 22780 -p -r pidof backend # Now we retrieve PID of our application but viewed from within the namespace
6 # ha like before :wink
nsenter -t 22780 -p -n -i -r -- lldb -p 6
(lldb) # Hourra
```


# Grand Final

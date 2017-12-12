/// simple timer
module timer;

import blockingqueue;
import core.thread;
import std.experimental.logger;
import std.string;

alias Runnable = void delegate();
struct Task
{
    import std.datetime;

    Runnable run;
    SysTime at;
    bool due()
    {
        return at <= Clock.currTime;
    }

    Duration remainingDuration()
    {
        return at - Clock.currTime;
    }
}

class Timer : Thread
{
    import std.datetime;

    string name;
    shared(BlockingQueue!Task) tasks;
    bool finished = false;

    this(string name)
    {
        this.name = "Timer(%s)".format(name);
        tasks = cast(shared) new BlockingQueue!Task;
        super(&run);
    }

    void runIn(Runnable run, Duration delta) shared
    {
        runAt(run, Clock.currTime() + delta);
    }

    void runAt(Runnable run, SysTime at) shared
    {
        tasks.add(Task(run, at));
    }

    void shutdown() shared
    {
        runAt(() => finish(), Clock.currTime);
    }

    private void finish() shared
    {
        finished = true;
    }

    private void run()
    {
        scope (exit)
        {
            info("%s finished".format(name));
        }
        Thread.getThis.name = name;

        while (!finished)
        {
            tasks.remove.run();
        }
    }
}

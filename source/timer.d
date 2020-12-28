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
    BlockingQueue!Task tasks;
    bool finished = false;

    this(string name)
    {
        this.name = "Timer(%s)".format(name);
        tasks = new BlockingQueue!Task;
        super(&run);
    }

    Timer start()
    {
        super.start();
        return this;
    }

    void runIn(Runnable run, Duration delta)
    {
        runAt(run, Clock.currTime() + delta);
    }

    void runAt(Runnable run, SysTime at)
    {
        tasks.add(Task(run, at));
    }

    void shutdown()
    {
        runAt(() => finish(), Clock.currTime);
    }

    private void finish()
    {
        finished = true;
    }

    private void run()
    {
        Thread.getThis.name = name;
        while (!finished)
        {
            tasks.remove.run();
        }
    }
}

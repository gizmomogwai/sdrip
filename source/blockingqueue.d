/// simple blocking queue
module blockingqueue;

class BlockingQueue(T)
{
    import core.sync.condition;
    import core.sync.mutex;
    import std.container;

    private Mutex mutex;
    private Condition condition;
    private DList!T items;

    public this()
    {
        mutex = new Mutex();
        condition = new Condition(mutex);
    }

    void add(T item) shared
    {
        synchronized (mutex)
        {
            (cast() items).insertBack(item);
            (cast() condition).notifyAll();
        }
    }

    T remove() shared
    {
        synchronized (mutex)
        {
            while ((cast() items).empty())
            {
                (cast() condition).wait();
            }

            while (!(cast() items).front.due)
            {
                auto remaining = (cast() items).front.remainingDuration;
                (cast() condition).wait(remaining);
            }

            T res = (cast() items).front;
            (cast() items).removeFront;
            return res;
        }
    }
}

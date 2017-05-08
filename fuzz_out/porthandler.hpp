#include <map>
#include <string>
#include <iostream>
#include "portstorage.hpp"

template<typename Value, typename Key>
class PortHandler
{
public:
    PortHandler() {}
    ~PortHandler() 
	{
	    for (typename std::map<Key, Value*>::iterator it = m_ports.begin(); it != m_ports.end(); ++it)
	    {
		delete it->second;
	    }
	}

    void* getPort(Key key, std::string name)
	{
	    typename std::map<Key, Value*>::iterator it = m_ports.find(key);
	    if (it != m_ports.end())
	    {
		return (void*)m_ports[key];
	    }
	    else
	    {
		Value* val = new Value(name);
		m_ports[key] = val;
		PortStorage::AddRegeneratable(new Regeneratable_Impl<Value*>(val), name);
		return (void*)m_ports[key];
	    }
	}

    void RegeneratePorts(const std::map<std::string, std::vector<int> > &vars)
	{
	    for (typename std::map<Key, Value*>::iterator it = m_ports.begin(); it != m_ports.end(); ++it)
	    {
		it->second->Regenerate(vars);
	    }
	}
private:
    std::map<Key, Value*> m_ports;
};


//GetPort<PortType, KeyType>(key, name)
template<typename Value, typename Key>
Value* GetPort(Key key, std::string name)
{
    static PortHandler<Value, Key> portHandler;
    return ((Value*)portHandler.getPort(key, name));
}

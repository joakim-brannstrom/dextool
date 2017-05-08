#ifndef PORTSTORAGE_HPP
#define PORTSTORAGE_HPP

#include <string>
#include <map>
#include <iostream>
#include <vector>
#include <map>

using namespace std;

class I_Regeneratable
{
public:
    virtual ~I_Regeneratable() {}
    virtual void Regenerate() = 0;
    virtual void Regenerate(const map<string, vector<vector<int> > > &vars, const int64_t &curr_cycles) = 0;
    virtual std::string getNamespace() = 0;
};

template<class P>
class Regeneratable_Impl : public I_Regeneratable
{
public:
    Regeneratable_Impl(P pp)
    {
	p = pp;
    }

    ~Regeneratable_Impl()
    {
	   
    }
    
    //Non-static
    void Regenerate()
    {
	p->Regenerate();
    }

    //Static
    void Regenerate(const map<string, vector<vector<int> > > &vars, const int64_t &curr_cycles)
    {
	p->Regenerate(vars, curr_cycles);
    }

    std::string getNamespace() 
    {
	return p->getNamespace();
    }

private:
    P p;
};

namespace PortStorage //TODO: Put in a class, with destructors and such
{
    void AddRegeneratable(I_Regeneratable* regen, string name);
    void Regenerate();
    void Regenerate(const map<string, map<string, vector<vector<int> > > > &namespaces, const int64_t &curr_cycles);
    void CleanUp(); 
}

#endif

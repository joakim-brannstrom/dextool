#ifndef PORTENVIRONMENT_HPP
#define PORTENVIRONMENT_HPP

#include <string>
#include <vector>
#include <map>
#include "porthandler.hpp"

class PortEnvironment
{
public:
    /*
      Constructor doing nothing...
     */
    PortEnvironment();

    /*
      Empty init function. Should be used for initializing the port environment.
     */
    static bool init();

    /*
      Empty quit function. Should be used for deinitializing the port environment.
     */
    static void quit();

    /*
      Creates a requirer/provider for a port. For an example usage, see the dummyRequirer.cpp and 
      dummyProvider.cpp implementations of Create_Instance.
      Template parameters:
        ReturnType: An implementation of a requirer/provider (Bar_Requirer_Impl). It is expected that the 
                    constructor of ReturnType takes one paramters, which is a pointer to a PortBaseType (I_Bar*).
	PortBaseType: The base class for the port to be stores in ReturnType (I_Bar).
	PortType: An implementation of PortBaseType (Bar_Impl).
	KeyType: The key type used in Create_Instance (const std::string&)

      Parameters:
        key: The key used as a parameter to Create_Instance.
	name: A name given to the port for loggin purposes.

      Returns a reference to the newly created requirer/provider.

      TODO: deallocate the memory created from this function. 
    */
    template <typename ReturnType, typename PortBaseType, typename PortType, typename KeyType>
    static ReturnType& createPort(KeyType key, std::string name)
    {
	return *(new ReturnType((PortBaseType*)GetPort<PortType, KeyType>(key, name)));
    }
    
private:
};

#endif

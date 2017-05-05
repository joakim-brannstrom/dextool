#include "string.hpp" //TO be changed

namespace Ops_Mode {
    namespace Ops_State {
        namespace Requirer { ////////////
            class I_Ops_State {
                public:
                    I_Ops_State(void);
                    virtual ~I_Ops_State(void);

                    virtual const Ops_Mode::Ops_State::Ops_State_type& Get_Ops_State(void) const;
                    virtual Ops_Mode::Ops_State_type::Enum Get_Ops_State_Ops_State(void) const;
                    virtual void Ops_State_Ops_State_Changed(const Ops_Mode::Ops_State_type::Enum New_Val) =0;
                    virtual Ops_Mode::Some_data_qual_type::Enum Get_Ops_State_Ops_State_Quality(void) const;
                    virtual void Ops_State_Ops_State_Quality_Changed(const Ops_Mode::Ops_Mode_Quality_Type::Enum New_Val) = 0;
            }
        }
    }
}

namespace Ops_Mode {
    namespace Ops_State {
        namespace Provider { ////////////
            class I_Ops_State {
                public:
                    I_Ops_State(void);
                    virtual ~I_Ops_State(void);

                    virtual const Ops_Mode::Ops_State::Ops_State_type& Get_Ops_State(void) const;
                    virtual void Put_Ops_State(const Ops_Mode::Ops_State_type::Enum Ops_State, const Ops_Mode::Some_data_qual_type::Enum Ops_State_qual) const = 0;

                    virtual bool Will_data_on_Ops_State_be_sent() const = 0;
            }
        }
    }
}
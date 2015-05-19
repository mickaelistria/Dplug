module dplug.plugin.fpcontrol;

import core.cpuid;
import std.math;

/// This struct ensures that floating point is save/restored and set consistently in plugin callbacks.
struct FPControl
{
    void initialize() @nogc
    {
        // disable FP exceptions
        if(FloatingPointControl.hasExceptionTraps)
            fpctrl.disableExceptions(FloatingPointControl.allExceptions);

        // force round to nearest
        fpctrl.rounding(FloatingPointControl.roundToNearest);

        version(X86)
        {
            sseState = getSSEControlState();
            setSSEControlState(0x9fff); // Flush denormals to zero + Denormals Are Zeros + all exception masked
        }
    }

    ~this() @nogc
    {
        version(X86)
        {
            // restore SSE2 LDMXCSR and STMXCSR load and write the MXCSR 
            setSSEControlState(sseState);
        }
    }

    FloatingPointControl fpctrl; // handles save/restore

    version(X86)
    {
        uint sseState;
    }
}


version(X86)
{
    version(D_InlineAsm_X86)
        version = InlineX86Asm;
    else version(D_InlineAsm_X86_64)
        version = InlineX86Asm;


    /// Get SSE control register
    uint getSSEControlState() @trusted nothrow @nogc
    {
        version (InlineX86Asm)
        {
            uint controlWord;
            static if( __VERSION__ >= 2067 )
                mixin("asm nothrow @nogc { stmxcsr controlWord; }");
            else
                mixin("asm { stmxcsr controlWord; }");
            
            return controlWord;
        }
        else
            assert(0, "Not yet supported");
    }

    /// Sets SSE control register
    void setSSEControlState(uint controlWord) @trusted nothrow @nogc
    {
        version (InlineX86Asm)
        {
            static if( __VERSION__ >= 2067 )
                mixin("asm nothrow @nogc { ldmxcsr controlWord; }");
            else
                mixin("asm { ldmxcsr controlWord; }");
        }
        else
            assert(0, "Not yet supported");
    }
}
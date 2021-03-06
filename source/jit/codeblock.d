/*****************************************************************************
*
*                      Higgs JavaScript Virtual Machine
*
*  This file is part of the Higgs project. The project is distributed at:
*  https://github.com/maximecb/Higgs
*
*  Copyright (c) 2012-2013, Maxime Chevalier-Boisvert. All rights reserved.
*
*  This software is licensed under the following license (Modified BSD
*  License):
*
*  Redistribution and use in source and binary forms, with or without
*  modification, are permitted provided that the following conditions are
*  met:
*   1. Redistributions of source code must retain the above copyright
*      notice, this list of conditions and the following disclaimer.
*   2. Redistributions in binary form must reproduce the above copyright
*      notice, this list of conditions and the following disclaimer in the
*      documentation and/or other materials provided with the distribution.
*   3. The name of the author may not be used to endorse or promote
*      products derived from this software without specific prior written
*      permission.
*
*  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
*  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
*  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
*  NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
*  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
*  NOT LIMITED TO PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
*  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
*  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
*  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
*  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*
*****************************************************************************/

module jit.codeblock;

import core.sys.posix.unistd;
import core.sys.posix.sys.mman;
import core.memory;
import std.stdio;
import std.string;
import std.array;
import std.stdint;

/**
Low-level machine code block implementation.
Stores generated machine code, external references and exposed labels.
*/
class CodeBlock
{
    /// Memory block size
    private size_t size;

    /// Memory block
    private ubyte* memBlock;

    /// Current writing position
    private size_t writePos;

    /// Exported labels in this block
    private size_t exports[string];

    this(size_t size)
    {
        assert (
            size > 0,
            "cannot create zero-sized memory block"
        );

        // Map the memory as executable
        this.memBlock = cast(ubyte*)mmap(
            null,
            size,
            PROT_READ | PROT_WRITE | PROT_EXEC,
            MAP_PRIVATE | MAP_ANON,
            -1,
            0
        );

        // Check that the memory mapping was successful
        if (this.memBlock == MAP_FAILED)
            throw new Error("mmap call failed");

        //writefln("memBlock: %s", this.memBlock);
        //writefln("pa: %s", pa);

        this.size = size;

        this.writePos = 0;
    }

    ~this()
    {
        //writefln("freeing executable memory: %s", this.memBlock);

        auto ret = munmap(this.memBlock, this.size);

        if (ret != 0)
            throw new Error("munmap call failed");
    }

    /**
    Print the code block as a string
    */
    override string toString()
    {
        auto app = appender!string();

        for (size_t i = 0; i < this.writePos; ++i)
        {
            auto b = this.memBlock[i];

            if (i != 0)
                app.put(' ');

            app.put(xformat("%02X", b));
        }

        return app.data;
    }

    /**
    Get the size of the code block
    */
    auto length()
    {
        return size;
    }

    /**
    Get a direct pointer into the executable memory block
    */
    auto getAddress(size_t index = 0)
    {
        assert (
            index < size,
            "invalid index"
        );

        return &memBlock[index];
    }

    /**
    Get the address of an exported label in the code block
    */
    auto getExportAddr(string name)
    {
        assert (
            name in this.exports,
            "invalid exported label"
        );

        return getAddress(this.exports[name]);
    }

    /**
    Clear the contents of the code block
    */
    void clear()
    {
        this.writePos = 0;
    }

    /**
    Set the current write position
    */
    void setWritePos(size_t pos)
    {
        assert (
            pos < size,
            "invalid code block position"
        );

        writePos = pos;
    }

    /**
    Get the current write position
    */
    size_t getWritePos()
    {
        return writePos;
    }

    /**
    Write a byte at the current position
    */
    void writeByte(ubyte val)
    {
        assert (
            this.memBlock,
            "invalid memory block"
        );

        assert (
            this.writePos + 1 <= this.size,
            "no space to write byte in code block"
        );

        this.memBlock[this.writePos] = val;

        this.writePos += 1;
    }

    /**
    Write a sequence of bytes at the current position
    */
    void writeBytes(immutable ubyte[] bytes)
    {
        foreach (b; bytes)
            writeByte(b);
    }

    /**
    Write a signed integer at the current position
    */
    void writeInt(uint64_t val, size_t numBits)
    {
        assert (
            numBits > 0 && numBits % 8 == 0,
            "the number of bits must be a positive multiple of 8"
        );

        /*
        assert (
            num_ge(val, getIntMin(numBits)) &&
            num_le(val, getIntMax(numBits, true)),
            'integer value does not fit within ' + numBits + ' bits: ' + val
        );
        */

        // Compute the size in bytes
        auto numBytes = numBits / 8;

        // Write out the bytes
        for (size_t i = 0; i < numBytes; ++i)
        {
            auto byteVal = cast(ubyte)(val & 0xFF);

            this.writeByte(byteVal);

            val >>= 8;
        }
    }

    /**
    Write a link value at the current position
    */
    /*
    writeLink(linkVal, numBits)
    {
        assert (
            numBits === 32 || numBits === 64,
            'invalid link value size'
        );

        // Store the link value and its position
        this.imports.push(
            {
                value: linkVal,
                pos: this.writePos
            }
        );

        // Compute the size in bytes
        var numBytes = numBits / 8;

        // Write placeholder bytes for the value
        for (var i = 0; i < numBytes; ++i)
            this.writeByte(0);
    }
    */

    /**
    Read the byte at the given index
    */
    ubyte readByte(size_t index)
    {
        assert (
            index < size
        );

        return memBlock[index];
    }

    /**
    Add an exported label at the the current position
    */
    void exportLabel(string name)
    {
        assert (
            name !in this.exports,
            "exported label already exists: \"" ~ name ~ "\""
        );

        // Store the link value and its position
        this.exports[name] = this.writePos;
    }
}


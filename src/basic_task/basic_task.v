module basic_task(
    // ==================== 输入信号 ====================
    input CLR,                 // 异步清零/复位信号（低电平有效）
    input SWA, SWB, SWC,       // 控制台开关：用于选择系统运行模式（如自动运行、读写内存、读写寄存器等）
    input IR4, IR5, IR6, IR7,  // 指令码：来自指令寄存器(IR)的高4位，即操作码(Opcode)
    input W1, W2, W3, T3,      // 时序节拍信号：W1/W2/W3为控制内部组合逻辑的节拍，T3为触发状态更新的时钟边沿
    input C, Z,                // 状态标志位：来自ALU的进位标志(C)和零标志(Z)，用于条件跳转指令(JC, JZ)

    // ==================== 输出信号 ====================
    // （输出到TEC-8数据通路及其他模块的控制信号）
    
    // --- 寄存器打入/写入控制 ---
    output reg DRW,            // 目的寄存器写使能 (Data Register Write)
    output reg LPC,            // 程序计数器PC打入使能 (Load PC)
    output reg LAR,            // 地址寄存器AR打入使能 (Load AR)
    output reg LIR,            // 指令寄存器IR打入使能 (Load IR)
    
    // --- PC与AR控制 ---
    output reg PCINC,          // 程序计数器PC加1使能
    output reg PCADD,          // 程序计数器PC加上相对偏移量 (用于跳转指令)
    output reg ARINC,          // 地址寄存器AR加1使能
    
    // --- ALU(算术逻辑单元)控制 ---
    output reg S0, S1, S2, S3, // ALU功能选择控制码
    output reg M,              // ALU工作模式控制：0=算术运算，1=逻辑运算
    output reg CIN,            // ALU的低位进位输入
    output reg LDZ, LDC,       // ALU状态标志寄存器更新使能：Load Z (零标志), Load C (进位标志)
    
    // --- 数据总线源选择 (三态门使能) ---
    output reg ABUS,           // 允许ALU的计算结果输出到数据总线
    output reg SBUS,           // 允许控制台数据开关(SW)输出到数据总线
    output reg MBUS,           // 允许主存储器(Memory)的数据输出到数据总线
    
    // --- 访存控制与停机 ---
    output reg MEMW,           // 主存储器写使能信号 (Memory Write)
    output reg SHORT, LONG,    // 存储器读写周期长度控制（短周期/长周期）
    output reg STOP,           // 停机/暂停信号：用于单步执行或触发STP(停机)指令
    
    // --- 通用寄存器组(RF)选择控制 ---
    output reg SEL0, SEL1, SEL2, SEL3, // 寄存器组读写地址选择码
    output reg SELCTL          // 寄存器组选择控制使能
);


localparam [2:0]
    MODE_AUTO = 3'b000,
    MODE_READ_MEM = 3'b010,
    MODE_WRITE_MEM = 3'b001,
    MODE_READ_REG = 3'b011,
    MODE_WRITE_REG = 3'b100;

localparam [3:0]
    OPCODE_NOP = 4'b0000,
    OPCODE_ADD = 4'b0001,
    OPCODE_SUB = 4'b0010,
    OPCODE_AND = 4'b0011,
    OPCODE_INC = 4'b0100,
    OPCODE_LD  = 4'b0101,
    OPCODE_ST  = 4'b0110,
    OPCODE_JC  = 4'b0111,
    OPCODE_JZ  = 4'b1000,
    OPCODE_JMP = 4'b1001,
    OPCODE_OUT = 4'b1010,
    OPCODE_MOV = 4'b1011,
    OPCODE_CMP = 4'b1100,
    OPCODE_NOT = 4'b1101,
    OPCODE_STP = 4'b1110;

    // ---------- 内部状态信号（非外部引脚） ----------
    reg ST0;      // 子状态标志：0=操作第一步，1=第二步
    reg SST0;     // ST0翻转使能信号

    // ---------- 时序逻辑：管理ST0状态的更新 ----------
    always @(negedge T3 or negedge CLR) begin
        if (!CLR)
            ST0 <= 1'b0;
        else if (SST0)
            ST0 <= ~ST0;
    end

    // ---------- 组合逻辑：生成所有控制信号 ----------
    always @(*) begin
        // ---- 所有信号默认初始化（避免锁存器） ----
        DRW = 1'b0; LPC = 1'b0; LAR = 1'b0;
        PCINC = 1'b0; PCADD = 1'b0; ARINC = 1'b0;
        {S3, S2, S1, S0} = 4'b0000; M = 1'b0; CIN = 1'b0;
        ABUS = 1'b0; SBUS = 1'b0; MBUS = 1'b0;
        SHORT = 1'b0; LONG = 1'b0;
        LIR = 1'b0; LDZ = 1'b0; LDC = 1'b0; MEMW = 1'b0; STOP = 1'b0;
        {SEL3, SEL2, SEL1, SEL0} = 4'b0000; SELCTL = 1'b0;
        SST0 = 1'b0;   // 默认不翻转ST0

        if (!CLR) begin
            // 复位状态（所有信号已初始化为0）
        end else begin
            case ({SWC, SWB, SWA})
                // ----- MODE_AUTO: 取指（自动运行模式） -----
                MODE_AUTO: begin
                    if (ST0) begin          // ST0=1：第二个节拍
                        LIR = W1;
                        PCINC = W1;
                        if (W2) begin
                            case ({IR7, IR6, IR5, IR4})
                                OPCODE_NOP: ; // NOP
                                OPCODE_ADD: begin // ADD
                                    {S3, S2, S1, S0} = 4'b1001; // S=1001
                                    CIN = 1'b1; ABUS = 1'b1; DRW = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                end
                                OPCODE_SUB: begin // SUB
                                    {S3, S2, S1, S0} = 4'b0110; // S=0110
                                    ABUS = 1'b1; DRW = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                end
                                OPCODE_AND: begin // AND
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1011; // S=1011
                                    ABUS = 1'b1; DRW = 1'b1; LDZ = 1'b1;
                                end
                                OPCODE_INC: begin // INC
                                    {S3, S2, S1, S0} = 4'b0000; // S=0000
                                    ABUS = 1'b1; DRW = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                end
                                OPCODE_LD: begin // LD
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1010; // S=1010
                                    ABUS = 1'b1; LAR = 1'b1; LONG = 1'b1;
                                end
                                OPCODE_ST: begin // ST
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1111; // S=1111
                                    ABUS = 1'b1; LAR = 1'b1; LONG = 1'b1;
                                end
                                OPCODE_JC: begin // JC
                                    if (C == 1'b1) PCADD = 1'b1;
                                end
                                OPCODE_JZ: begin // JZ
                                    if (Z == 1'b1) PCADD = 1'b1;
                                end
                                OPCODE_JMP: begin // JMP
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1111; // S=1111
                                    ABUS = 1'b1; LPC = 1'b1;
                                end
                                OPCODE_OUT: begin // OUT
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1010; // S=1010
                                    ABUS = 1'b1;
                                end
                                OPCODE_MOV: begin // MOV
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1010; // S=1010
                                    ABUS = 1'b1; DRW = 1'b1;
                                end
                                OPCODE_CMP: begin // CMP
                                    {S3, S2, S1, S0} = 4'b0110; // S=0110
                                    ABUS = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                end
                                OPCODE_NOT: begin // NOT
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b0000; // S=0000
                                    ABUS = 1'b1; DRW = 1'b1; LDC = 1'b1;
                                end
                                OPCODE_STP: begin // STP
                                    STOP = 1'b1;
                                end
                                default: ;
                            endcase
                        end
                        else if (W3) begin
                            case ({IR7, IR6, IR5, IR4})
                                OPCODE_LD: begin // LD回写
                                    DRW = 1'b1; MBUS = 1'b1;
                                end
                                OPCODE_ST: begin // ST回写
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1010; // S=1010
                                    ABUS = 1'b1; MEMW = 1'b1;
                                end
                                default: ;
                            endcase
                        end
                    end else begin          // ST0=0：第一个节拍
                        STOP = W1;
                        
                        SBUS = W2;
                        LPC = W2;
                        SST0 = W2;
                    end
                end

                // ----- MODE_WRITE_MEM: 写存储器（控制台方式） -----
                MODE_WRITE_MEM: begin
                    if (ST0) begin
                        if (W1) begin
                            SBUS = 1'b1; MEMW = 1'b1; ARINC = 1'b1; STOP = 1'b1;
                            SHORT = 1'b1; SELCTL = 1'b1;
                        end
                    end else begin
                        if (W1) begin
                            SBUS = 1'b1; LAR = 1'b1; STOP = 1'b1; SST0 = 1'b1;
                            SHORT = 1'b1; SELCTL = 1'b1;
                        end
                    end
                end

                // ----- MODE_READ_MEM: 读存储器（控制台方式） -----
                MODE_READ_MEM: begin
                    if (ST0) begin
                        if (W1) begin
                            MBUS = 1'b1; ARINC = 1'b1; STOP = 1'b1;
                            SHORT = 1'b1; SELCTL = 1'b1;
                        end
                    end else begin
                        if (W1) begin
                            SBUS = 1'b1; LAR = 1'b1; STOP = 1'b1; SST0 = 1'b1;
                            SHORT = 1'b1; SELCTL = 1'b1;
                        end
                    end
                end

                // ----- MODE_READ_REG: 读寄存器（控制台方式） -----
                MODE_READ_REG: begin
                    SELCTL = W1 | W2;
                    STOP = W1 | W2;
                    SEL3 = W2;
                    SEL2 = 1'b0;
                    SEL1 = W1;
                    SEL0 = 1'b1;
                end

                // ----- MODE_WRITE_REG: 写寄存器（控制台方式） -----
                MODE_WRITE_REG: begin
                    SELCTL = W1 | W2;
                    STOP = W1 | W2;
                    SBUS = W1 | W2;
                    DRW = W1 | W2;

                    SEL3 = ST0;
                    SEL2 = W2;
                    SEL1 = (W1 & ~ST0) | (W2 & ST0);
                    SEL0 = W1;

                    SST0 = W2 & ~ST0;   // 请求翻转ST0
                end

                default: ;
            endcase
        end
    end
endmodule

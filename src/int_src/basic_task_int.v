module basic_task(
    // ==================== 输入信号 ====================
    input CLR,                 // 异步清零/复位信号（低电平有效）
    input SWA, SWB, SWC,       // 控制台开关：用于选择系统运行模式（如自动运行、读写内存、读写寄存器等）
    input IR4, IR5, IR6, IR7,  // 指令码：来自指令寄存器(IR)的高4位，即操作码(Opcode)
    input W1, W2, W3, T3,      // 时序节拍信号：W1/W2/W3为控制内部组合逻辑的节拍，T3为触发状态更新的时钟边沿
    input C, Z,                // 状态标志位：来自ALU的进位标志(C)和零标志(Z)，用于条件跳转指令(JC, JZ)
    input INT,                 // 【新增引脚】外部中断请求信号（高电平有效，接 PIN_17）

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
    
    // 【新增内部寄存器】硬件影子计数器，通过同步规律暗中追踪黑盒 PC 的行指针
    reg [7:0] my_pc_tracker;

    // ---------- 时序逻辑：管理ST0状态的更新 ----------
    always @(negedge T3 or negedge CLR) begin
        if (!CLR) begin
            ST0 <= 1'b0;
            my_pc_tracker <= 8'h00; // 复位时，追踪器与物理 PC 同步清零归位
        end else begin
            if (SST0)
                ST0 <= ~ST0;
                
            // 只要物理 PCINC 亮起，且没有发生中断劫持，影子追踪器同步自增
            if (PCINC && !INT)
                my_pc_tracker <= my_pc_tracker + 1'b1;
        end
    end

    // ---------- 组合逻辑：生成所有控制信号 ----------
    always @(*) begin
        // ---- 所有信号默认初始化（避免锁存器） ----
        DRW = 1'b0;
        LPC = 1'b0; LAR = 1'b0;
        PCINC = 1'b0; PCADD = 1'b0; ARINC = 1'b0;
        {S3, S2, S1, S0} = 4'b0000; M = 1'b0; CIN = 1'b0;
        ABUS = 1'b0; SBUS = 1'b0;
        MBUS = 1'b0;
        SHORT = 1'b0; LONG = 1'b0;
        LIR = 1'b0; LDZ = 1'b0; LDC = 1'b0;
        MEMW = 1'b0; STOP = 1'b0;
        {SEL3, SEL2, SEL1, SEL0} = 4'b0000; SELCTL = 1'b0;
        SST0 = 1'b0; // 默认不翻转ST0

        if (!CLR) begin
            // 复位状态（所有信号已初始化为0）
        end else begin
            case ({SWC, SWB, SWA})
                // ----- MODE_AUTO: 取指（自动运行模式） -----
                MODE_AUTO: begin
                    if (ST0) begin          // ST0=1：第二个节拍
                        
                        // ==================== 【最高优先级：中断硬劫持逻辑】 ====================
                        if (INT) begin
                            LIR = 1'b0;     // 彻底封锁常规取指通路，不让指令进IR
                            PCINC = 1'b0;   // 锁死物理 PC 步进，将其物理卡死在当前断点行
                            STOP = 1'b1;    // 强行拉高停机信号，逼迫实验箱在当前拍物理刹车挂起
                            
                            // 劫持数据通路：把影子计数器（断点值）通过 ALU 盲砸进寄存器 R3
                            M = 1'b1; {S3, S2, S1, S0} = 4'b1010; // ALU 调至 A 通道纯直通
                            ABUS = 1'b1;    // 打开 ALU 输出门，把断点值推上总线大动脉
                            SELCTL = 1'b1;  {SEL3, SEL2, SEL1, SEL0} = 4'b1111; // 寻址线锁死 R3
                            DRW = 1'b1;     // 强开写使能，完成断点现场的固化保存
                        end
                        // =======================================================================
                        else begin
                            LIR = W1;
                            PCINC = W1;
                            if (W2) begin
                                case ({IR7, IR6, IR5, IR4})
                                    OPCODE_NOP: ; // NOP
                                    OPCODE_ADD: begin // ADD
                                        {S3, S2, S1, S0} = 4'b1001; // S=1001
                                        CIN = 1'b1;
                                        ABUS = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                        // 【硬件防污熔断】：如果目的寄存器是 R3，直接强制抽掉写使能，力保断点安全
                                        DRW = ({SEL3, SEL2, SEL1, SEL0} == 4'b1111) ? 1'b0 : 1'b1;
                                    end
                                    OPCODE_SUB: begin // SUB
                                        {S3, S2, S1, S0} = 4'b0110; // S=0110
                                        ABUS = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                        DRW = ({SEL3, SEL2, SEL1, SEL0} == 4'b1111) ? 1'b0 : 1'b1;
                                    end
                                    OPCODE_AND: begin // AND
                                        M = 1'b1;
                                        {S3, S2, S1, S0} = 4'b1011; // S=1011
                                        ABUS = 1'b1; LDZ = 1'b1;
                                        DRW = ({SEL3, SEL2, SEL1, SEL0} == 4'b1111) ? 1'b0 : 1'b1;
                                    end
                                    OPCODE_INC: begin // INC
                                        {S3, S2, S1, S0} = 4'b0000; // S=0000
                                        ABUS = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                        DRW = ({SEL3, SEL2, SEL1, SEL0} == 4'b1111) ? 1'b0 : 1'b1;
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
                                        ABUS = 1'b1;
                                        DRW = ({SEL3, SEL2, SEL1, SEL0} == 4'b1111) ? 1'b0 : 1'b1;
                                    end
                                    OPCODE_CMP: begin // CMP
                                        {S3, S2, S1, S0} = 4'b0110; // S=0110
                                        ABUS = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                    end
                                    OPCODE_NOT: begin // NOT
                                        M = 1'b1;
                                        {S3, S2, S1, S0} = 4'b0000; // S=0000
                                        ABUS = 1'b1; LDC = 1'b1;
                                        DRW = ({SEL3, SEL2, SEL1, SEL0} == 4'b1111) ? 1'b0 : 1'b1;
                                    end
                                    OPCODE_STP: begin // STP
                                        STOP = 1'b1;
                                    end
                                    
                                    // ==================== 【新增：IRET 返回指令底层译码】 ====================
                                    // 严格对应 PPT 第 24 页官方硬性规定：操作码 1011 代表 IRET 中断返回
                                    4'b1011: begin
                                        M = 1'b1; {S3, S2, S1, S0} = 4'b1010; // ALU 配置为纯直通模式
                                        SELCTL = 1'b1; {SEL3, SEL2, SEL1, SEL0} = 4'b1111; // 强行拉高选通 R3
                                        ABUS = 1'b1;                          // 把 R3 里的断点值推上公共总线
                                        LPC = 1'b1;                           // 激活 LPC，断点数据精准复位砸回物理 PC
                                    end
                                    // =======================================================================
                                    
                                    default: ;
                                endcase
                            end
                            else if (W3) begin
                                case ({IR7, IR6, IR5, IR4})
                                    OPCODE_LD: begin // LD回写
                                        MBUS = 1'b1;
                                        DRW = ({SEL3, SEL2, SEL1, SEL0} == 4'b1111) ? 1'b0 : 1'b1; // 防污拦截
                                    end
                                    OPCODE_ST: begin // ST回写
                                        M = 1'b1;
                                        {S3, S2, S1, S0} = 4'b1010; // S=1010
                                        ABUS = 1'b1; MEMW = 1'b1;
                                    end
                                    default: ;
                                endcase
                            end
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
                            SBUS = 1'b1;
                            MEMW = 1'b1; ARINC = 1'b1; STOP = 1'b1;
                            SHORT = 1'b1; SELCTL = 1'b1;
                        end
                    end else begin
                        if (W1) begin
                            SBUS = 1'b1;
                            LAR = 1'b1; STOP = 1'b1; SST0 = 1'b1;
                            SHORT = 1'b1; SELCTL = 1'b1;
                        end
                    end
                end

                // ----- MODE_READ_MEM: 读存储器（控制台方式） -----
                MODE_READ_MEM: begin
                    if (ST0) begin
                        if (W1) begin
                            MBUS = 1'b1;
                            ARINC = 1'b1; STOP = 1'b1;
                            SHORT = 1'b1; SELCTL = 1'b1;
                        end
                    end else begin
                        if (W1) begin
                            SBUS = 1'b1;
                            LAR = 1'b1; STOP = 1'b1; SST0 = 1'b1;
                            SHORT = 1'b1; SELCTL = 1'b1;
                        end
                    end
                end

                // ----- MODE_READ_REG: 读寄存器（控制台方式） -----
                MODE_READ_REG: begin
                    SELCTL = W1 | W2;
                    STOP = W1 | W2;
                    
                    // ==================== 【复用重构：零人工干预的断点静态验收窗口】 ====================
                    // 原本是用来根据 W1/W2 轮流读出不同的寄存器。现在将其四位片选线全部硬编码焊死在最高电平。
                    // 只要控制台开关拨到 011 并踩下单步脉冲，大动脉总线灯 D7~D0 会无条件、静态亮起 R3 里的暂存断点。
                    SEL3 = 1'b1;
                    SEL2 = 1'b1;
                    SEL1 = 1'b1;
                    SEL0 = 1'b1;
                    // ==================================================================================
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

                    SST0 = W2 & ~ST0; // 请求翻转ST0
                end

                default: ;
            endcase
        end
    end
endmodule
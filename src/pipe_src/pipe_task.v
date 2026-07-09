module pipe_task(
    // ==================== �����ź� ====================
    input CLR,                 // �첽����/��λ�źţ��͵�ƽ��Ч��
    input SWA, SWB, SWC,       // ����̨���أ�����ѡ��ϵͳ����ģʽ�����Զ����С���д�ڴ桢��д�Ĵ����ȣ�
    input IR4, IR5, IR6, IR7,  // ָ���룺����ָ��Ĵ���?(IR)�ĸ�4λ����������(Opcode)
    input W1, W2, W3, T3,      // ʱ������źţ�W1/W2/W3Ϊ�����ڲ�����߼��Ľ��ģ�T3Ϊ����״̬���µ�ʱ�ӱ���
    input C, Z,                // ״̬��־λ������ALU�Ľ�λ��־(C)������?(Z)������������תָ��(JC, JZ)

    // ==================== ����ź�? ====================
    // �������TEC-8����ͨ·������ģ��Ŀ����źţ�?
    
    // --- �Ĵ�������/д�����? ---
    output reg DRW,            // Ŀ�ļĴ���дʹ�� (Data Register Write)
    output reg LPC,            // ���������PC����ʹ�� (Load PC)
    output reg LAR,            // ��ַ�Ĵ���AR����ʹ�� (Load AR)
    output reg LIR,            // ָ��Ĵ���IR����ʹ�� (Load IR)
    
    // --- PC��AR���� ---
    output reg PCINC,          // ���������PC��1ʹ�ܣ�T3�����������������������?
    output reg PCADD,          // ���������PC�������ƫ����? (������תָ��)
    output reg ARINC,          // ��ַ�Ĵ���AR��1ʹ��
    
    // --- ALU(�����߼���Ԫ)���� ---
    output reg S0, S1, S2, S3, // ALU����ѡ�������?
    output reg M,              // ALU����ģʽ���ƣ�0=�������㣬1=�߼�����
    output reg CIN,            // ALU�ĵ�λ��λ����
    output reg LDZ, LDC,       // ALU״̬��־�Ĵ�������ʹ�ܣ�Load Z (����?), Load C (��λ��־)
    
    // --- ��������Դѡ�� (��̬��ʹ��) ---
    output reg ABUS,           // ����ALU�ļ������������������?
    output reg SBUS,           // ��������̨���ݿ���(SW)�������������?
    output reg MBUS,           // �������洢��(Memory)�������������������?
    
    // --- �ô������ͣ��? ---
    output reg MEMW,           // ���洢��дʹ���ź� (Memory Write)
    output reg SHORT, LONG,    // �洢����д���ڳ��ȿ��ƣ�������/�����ڣ�
    output reg STOP,           // ͣ��/��ͣ�źţ����ڵ���ִ�л򴥷�STP(ͣ��)ָ��
    
    // --- ͨ�üĴ�����(RF)ѡ�����? ---
    output reg SEL0, SEL1, SEL2, SEL3, // �Ĵ������д��ַѡ����?
    output reg SELCTL          // �Ĵ�����ѡ�����ʹ��?
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

    // ---------- �ڲ�״̬�źţ����ⲿ���ţ� ----------
    reg ST0;        // ��״̬��־��0=������һ����1=�ڶ���
    reg SST0;       // ST0��תʹ���ź�
    reg pcinc_reg;  // PCINC�����źţ�����߼���λ��T3�������浽PCINC���������������?

	reg lir_reg;

    // ---------- ʱ���߼�������ST0״̬�ĸ��� ----------
    always @(negedge T3 or negedge CLR) begin
        if (!CLR)
            ST0 <= 1'b0;
        else if (SST0)
            ST0 <= ~ST0;
    end

    // ---------- ʱ���߼����ӳ�PCINC��T3���أ�������ȷ��LIR���ȶ���PCINC��仯��?----------
    always @(posedge T3) begin
		PCINC <= pcinc_reg;
		LIR <= lir_reg;
	end


    // ---------- ����߼����������п����ź�? ----------
    always @(*) begin
        // ---- �����ź�Ĭ�ϳ�ʼ���������������� ----
        DRW = 1'b0; LPC = 1'b0; LAR = 1'b0;
        PCADD = 1'b0; ARINC = 1'b0;
        {S3, S2, S1, S0} = 4'b0000; M = 1'b0; CIN = 1'b0;
        ABUS = 1'b0; SBUS = 1'b0; MBUS = 1'b0;
        SHORT = 1'b0; LONG = 1'b0;
        lir_reg = 1'b0; LDZ = 1'b0; LDC = 1'b0; MEMW = 1'b0; STOP = 1'b0;
        {SEL3, SEL2, SEL1, SEL0} = 4'b0000; SELCTL = 1'b0;
        SST0 = 1'b0;
        pcinc_reg = 1'b0;   // Ĭ�ϲ�����PCINC

        if (!CLR) begin
            // ��λ״̬�������ź��ѳ�ʼ��Ϊ0��
        end else begin
            case ({SWC, SWB, SWA})
                // ----- MODE_AUTO: ȡָ���Զ�����ģʽ�� -----
                MODE_AUTO: begin
                    if (ST0) begin          // ST0=1���ڶ�������
                        if (W1) begin
                            case ({IR7, IR6, IR5, IR4})
                                OPCODE_NOP: begin // NOP
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_ADD: begin // ADD
                                    {S3, S2, S1, S0} = 4'b1001; // S=1001
                                    CIN = 1'b1; ABUS = 1'b1; DRW = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_SUB: begin // SUB
                                    {S3, S2, S1, S0} = 4'b0110; // S=0110
                                    ABUS = 1'b1; DRW = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_AND: begin // AND
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1011; // S=1011
                                    ABUS = 1'b1; DRW = 1'b1; LDZ = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_INC: begin // INC
                                    {S3, S2, S1, S0} = 4'b0000; // S=0000
                                    ABUS = 1'b1; DRW = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_LD: begin // LD
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1010; // S=1010
                                    ABUS = 1'b1; LAR = 1'b1; LONG = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_ST: begin // ST
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1111; // S=1111
                                    ABUS = 1'b1; LAR = 1'b1; LONG = 1'b1;
                                end
                                OPCODE_JC: begin // JC
                                    if (C == 1'b1) begin
                                        PCADD = 1'b1;
                                    end else begin
                                        lir_reg = 1'b1; pcinc_reg = 1'b1;
                                        SHORT = 1'b1;
                                    end
                                end
                                OPCODE_JZ: begin // JZ
                                    if (Z == 1'b1) begin
                                        PCADD = 1'b1;
                                    end else begin
                                        lir_reg = 1'b1; pcinc_reg = 1'b1;
                                        SHORT = 1'b1;
                                    end
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
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_MOV: begin // MOV
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1010; // S=1010
                                    ABUS = 1'b1; DRW = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_CMP: begin // CMP
                                    {S3, S2, S1, S0} = 4'b0110; // S=0110
                                    ABUS = 1'b1; LDZ = 1'b1; LDC = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_NOT: begin // NOT
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b0000; // S=0000
                                    ABUS = 1'b1; DRW = 1'b1; LDC = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                OPCODE_STP: begin // STP
                                    STOP = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                    SHORT = 1'b1;
                                end
                                default: ;
                            endcase
                        end
                        else if (W2) begin
                            case ({IR7, IR6, IR5, IR4})
                                OPCODE_LD: begin // LD��д
                                    DRW = 1'b1; MBUS = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                end
                                OPCODE_ST: begin // ST��д
                                    M = 1'b1;
                                    {S3, S2, S1, S0} = 4'b1010; // S=1010
                                    ABUS = 1'b1; MEMW = 1'b1;
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                end
                                OPCODE_JMP: begin // JMP
                                    lir_reg = 1'b1; pcinc_reg = 1'b1;
                                end
                                OPCODE_JC: begin // JC����
                                    lir_reg = C;
                                    pcinc_reg = C;
                                end
                                OPCODE_JZ: begin // JZ����
                                    lir_reg = Z;
                                    pcinc_reg = Z;
                                end
                                default: ;
                            endcase
                        end
                    end else begin          // ST0=0����һ������
                        STOP = W1;
                        
                        SBUS = W2;
                        LPC = W2;
                        LONG = W2;

                        lir_reg = W3;
                        pcinc_reg = W3;
                        SST0 = W3;
                    end
                end

                // ----- MODE_WRITE_MEM: д�洢��������̨��ʽ�� -----
                MODE_WRITE_MEM: begin
                    SST0 = W1 & ~ST0;
                    SBUS = W1;
                    MEMW = W1 & ST0;
                    ARINC = W1 & ST0;
                    STOP = W1;
                    SHORT = W1;
                    SELCTL = W1;
                    LAR = W1 & ~ST0;
                end

                // ----- MODE_READ_MEM: ���洢��������̨��ʽ�� -----
                MODE_READ_MEM: begin
                    SST0 = W1 & ~ST0;
                    MBUS = W1 & ST0;
                    SBUS = W1 & ~ST0;
                    ARINC = W1 & ST0;
                    STOP = W1;
                    SHORT = W1;
                    SELCTL = W1;
                    LAR = W1 & ~ST0;
                end

                // ----- MODE_READ_REG: ���Ĵ���������̨��ʽ�� -----
                MODE_READ_REG: begin
                    SELCTL = W1 | W2;
                    STOP = W1 | W2;
                    SEL3 = W2;
                    SEL2 = 1'b0;
                    SEL1 = W2;
                    SEL0 = 1'b1;
                end

                // ----- MODE_WRITE_REG: д�Ĵ���������̨��ʽ�� -----
                MODE_WRITE_REG: begin
                    SELCTL = W1 | W2;
                    STOP = W1 | W2;
                    SBUS = W1 | W2;
                    DRW = W1 | W2;

                    SEL3 = ST0;
                    SEL2 = W2;
                    SEL1 = (W1 & ~ST0) | (W2 & ST0);
                    SEL0 = W1;

                    SST0 = W2 & ~ST0;   // ����תST0
                end

                default: ;
            endcase
        end
    end
endmodule

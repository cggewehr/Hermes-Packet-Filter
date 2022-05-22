--------------------------------------------------------------------------------------- 
--                                    ROUTER
--
--
--                                    NORTH         LOCAL
--                      -----------------------------------
--                      |             ******       ****** |
--                      |             *FILA*       *FILA* |
--                      |             ******       ****** |
--                      |          *************          |
--                      |          *  ARBITRO  *          |
--                      | ******   *************   ****** |
--                 WEST | *FILA*   *************   *FILA* | EAST
--                      | ******   *  CONTROLE *   ****** |
--                      |          *************          |
--                      |             ******              |
--                      |             *FILA*              |
--                      |             ******              |
--                      -----------------------------------
--                                    SOUTH
--
--  As chaves realizam a transferýncia de mensagens entre nýcleos. 
--  A chave possui uma lýgica de controle de chaveamento e 5 portas bidirecionais:
--  East, West, North, South e Local. Cada porta possui uma fila para o armazenamento 
--  temporýrio de flits. A porta Local estabelece a comunicaýýo entre a chave e seu 
--  nýcleo. As demais portas ligam a chave ýs chaves vizinhas.
--  Os endereýos das chaves sýo compostos pelas coordenadas XY da rede de interconexýo, 
--  onde X ý a posiýýo horizontal e Y a posiýýo vertical. A atribuiýýo de endereýos ýs 
--  chaves ý necessýria para a execuýýo do algoritmo de chaveamento.
--  Os mýdulos principais que compýem a chave sýo: fila, ýrbitro e lýgica de 
--  chaveamento implementada pelo controle_mux. Cada uma das filas da chave (E, W, N, 
--  S e L), ao receber um novo pacote requisita chaveamento ao ýrbitro. O ýrbitro 
--  seleciona a requisiýýo de maior prioridade, quando existem requisiýýes simultýneas, 
--  e encaminha o pedido de chaveamento ý lýgica de chaveamento. A lýgica de 
--  chaveamento verifica se ý possývel atender ý solicitaýýo. Sendo possývel, a conexýo
--  ý estabelecida e o ýrbitro ý informado. Por sua vez, o ýrbitro informa a fila que 
--  comeýa a enviar os flits armazenados. Quando todos os flits do pacote foram 
--  enviados, a conexýo ý concluýda pela sinalizaýýo, por parte da fila, atravýs do 
--  sinal sender.
---------------------------------------------------------------------------------------
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.std_logic_unsigned.all;

use work.HermesPackage.all;

entity RouterCC is

    generic(
        address: regmetadeflit;
        EnablePacketFilter: boolean;
        --XMax: integer;
        --YMax: integer;
        XMax: regquartoflit;
        YMax: regquartoflit;
        TimeoutMax: integer
    );

    port(
        clock:     in  std_logic;
        reset:     in  std_logic;
        clock_rx:  in  regNport;
        rx:        in  regNport;
        data_in:   in  arrayNport_regflit;
        credit_o:  out regNport;    
        clock_tx:  out regNport;
        tx:        out regNport;
        data_out:  out arrayNport_regflit;
        credit_i:  in  regNport
    );

end RouterCC;

architecture RouterCC of RouterCC is

    signal h, ack_h, data_av, sender, data_ack: regNport := (others=>'0');
    signal data: arrayNport_regflit := (others=>(others=>'0'));
    signal mux_in, mux_out: arrayNport_reg3 := (others=>(others=>'0'));
    signal free: regNport := (others=>'0');

    signal packetFilterDataOut: arrayNport_regflit;
    signal packetFilterTx: regNport;
    signal bufferCreditO: regNport;

begin

    buffers: for i in 0 to NPORT - 1 generate

        buf: entity work.Hermes_buffer

            port map(
                clock => clock,
                reset => reset,
                --data_in => data_in(i),
                --rx => rx(i),
                data_in => packetFilterDataOut(i),
                rx => packetFilterTx(i),
                h => h(i),
                ack_h => ack_h(i),
                data_av => data_av(i),
                data => data(i),
                sender => sender(i),
                clock_rx => clock_rx(i),
                data_ack => data_ack(i),
                --credit_o => credit_o(i)
                credit_o => bufferCreditO(i)
            );

    end generate buffers; 

    PacketFilter: if EnablePacketFilter generate

        PacketFilter: entity work.PacketFilter

            generic map(
                XMax => XMax,
                YMax => YMax,
                TimeoutMax => TimeoutMax
            )

            port map(
                clk => clock,
                reset => reset,
                data_in => data_in(LOCAL),
                rx => rx(LOCAL),
                credit_o => credit_o(LOCAL),
                data_out => packetFilterDataOut(LOCAL),
                tx => packetFilterTx(LOCAL),
                credit_i => bufferCreditO(LOCAL)
            );
            
        PacketFilterGen: for i in 0 to NPORT - 1 generate

            ConnectIOGen: if i /= LOCAL generate
                packetFilterDataOut(i) <= data_in(i);
                packetFilterTx(i) <= rx(i);
                credit_o(i) <= bufferCreditO(i);
            end generate ConnectIOGen;  

        end generate PacketFilterGen;  

    end generate;

    NoPacketFilter: if not EnablePacketFilter generate

        NoPacketFilterGen: for i in 0 to NPORT - 1 generate
            packetFilterDataOut(i) <= data_in(i);
            packetFilterTx(i) <= rx(i);
            credit_o(i) <= bufferCreditO(i);
        end generate NoPacketFilterGen;  

    end generate;

    SwitchControl: entity work.SwitchControl

        port map(
            clock => clock,
            reset => reset,
            h => h,
            ack_h => ack_h,
            address => address,
            data => data,
            sender => sender,
            free => free,
            mux_in => mux_in,
            mux_out => mux_out
        );

    CrossBar: entity work.Hermes_crossbar

        port map(
            data_av => data_av,
            data_in => data,
            data_ack => data_ack,
            sender => sender,
            free => free,
            tab_in => mux_in,
            tab_out => mux_out,
            tx => tx,
            data_out => data_out,
            credit_i => credit_i
        );

    CLK_TX : for i in 0 to(NPORT-1) generate
        clock_tx(i) <= clock;
    end generate CLK_TX;  

end RouterCC;

// mm_env.sv - agent + scoreboard
class mm_env extends uvm_env;
    `uvm_component_utils(mm_env)

    axil_agent    agt;
    mm_scoreboard sb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = axil_agent::type_id::create("agt", this);
        sb  = mm_scoreboard::type_id::create("sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agt.mon.ap.connect(sb.analysis_export);
    endfunction

endclass

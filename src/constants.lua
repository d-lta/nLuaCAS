local errors = _G.errors
local ast = _G.ast or error("AST module required")
local diffAST = _G.diffAST or error("diffAST (symbolic differentiation) required")

local init = rawget(_G, "init")
local var = rawget(_G, "var") or require("var")


-- Because clearly physics constants need their own VIP section with metadata and a velvet rope
local physics_constants = {
    -- Fundamental constants
    g = {
        value = ast.number(9.80665),
        description = "Standard gravity",
        unit = "m/s²",
        category = "fundamental",
        symbol = "g"
    },
    c = {
        value = ast.number(299792458),
        description = "Speed of light in vacuum",
        unit = "m/s",
        category = "fundamental",
        symbol = "c"
    },
    h = {
        value = ast.number(6.62607015e-34),
        description = "Planck constant",
        unit = "J⋅s",
        category = "fundamental",
        symbol = "h"
    },
    hbar = {
        value = ast.number(1.054571817e-34),
        description = "Reduced Planck constant",
        unit = "J⋅s",
        category = "fundamental",
        symbol = "ℏ"
    },
    e = {
        value = ast.number(1.602176634e-19),
        description = "Elementary charge",
        unit = "C",
        category = "fundamental",
        symbol = "e"
    },
    
    -- Particle masses, because mass matters
    m_e = {
        value = ast.number(9.1093837015e-31),
        description = "Electron rest mass",
        unit = "kg",
        category = "particle_masses",
        symbol = "mₑ"
    },
    m_p = {
        value = ast.number(1.67262192369e-27),
        description = "Proton rest mass",
        unit = "kg",
        category = "particle_masses",
        symbol = "mₚ"
    },
    m_n = {
        value = ast.number(1.67492749804e-27),
        description = "Neutron rest mass",
        unit = "kg",
        category = "particle_masses",
        symbol = "mₙ"
    },
    
    -- Particle mass energies, because why not add energy to the mix
    m_e_eV = {
        value = ast.number(0.51099895000e6),
        description = "Electron mass energy",
        unit = "eV/c²",
        category = "particle_masses",
        symbol = "mₑc²"
    },
    m_p_eV = {
        value = ast.number(938.27208816e6),
        description = "Proton mass energy",
        unit = "eV/c²",
        category = "particle_masses",
        symbol = "mₚc²"
    },
    m_n_eV = {
        value = ast.number(939.56542052e6),
        description = "Neutron mass energy",
        unit = "eV/c²",
        category = "particle_masses",
        symbol = "mₙc²"
    },
    
    -- Atomic and molecular constants, because atoms deserve constants too
    mu = {
        value = ast.number(1.66053906660e-27),
        description = "Atomic mass unit",
        unit = "kg",
        category = "atomic",
        symbol = "μ"
    },
    u = {
        value = ast.number(1.66053906660e-27),
        description = "Atomic mass unit (alias)",
        unit = "kg",
        category = "atomic",
        symbol = "u"
    },
    N_A = {
        value = ast.number(6.02214076e23),
        description = "Avogadro's number",
        unit = "mol⁻¹",
        category = "atomic",
        symbol = "Nₐ"
    },
    k_B = {
        value = ast.number(1.380649e-23),
        description = "Boltzmann constant",
        unit = "J/K",
        category = "thermodynamic",
        symbol = "kᵦ"
    },
    R = {
        value = ast.number(8.314462618),
        description = "Gas constant",
        unit = "J/(mol⋅K)",
        category = "thermodynamic",
        symbol = "R"
    },
    
    -- Electromagnetic constants, because electricity and magnetism can't be ignored
    epsilon_0 = {
        value = ast.number(8.8541878128e-12),
        description = "Vacuum permittivity",
        unit = "F/m",
        category = "electromagnetic",
        symbol = "ε₀"
    },
    mu_0 = {
        value = ast.number(1.25663706212e-6),
        description = "Vacuum permeability",
        unit = "H/m",
        category = "electromagnetic",
        symbol = "μ₀"
    },
    Z_0 = {
        value = ast.number(376.730313668),
        description = "Vacuum impedance",
        unit = "Ω",
        category = "electromagnetic",
        symbol = "Z₀"
    },
    
    -- Atomic structure constants, because atoms have structure and that matters
    a_0 = {
        value = ast.number(5.29177210903e-11),
        description = "Bohr radius",
        unit = "m",
        category = "atomic",
        symbol = "a₀"
    },
    R_inf = {
        value = ast.number(1.0973731568160e7),
        description = "Rydberg constant",
        unit = "m⁻¹",
        category = "atomic",
        symbol = "R∞"
    },
    alpha = {
        value = ast.number(7.2973525693e-3),
        description = "Fine structure constant",
        unit = "dimensionless",
        category = "atomic",
        symbol = "α"
    },
    
    -- Energy constants, because energy is everything
    eV = {
        value = ast.number(1.602176634e-19),
        description = "Electron volt",
        unit = "J",
        category = "energy",
        symbol = "eV"
    },
    
    -- Other constants, because we need to fill space
    F = {
        value = ast.number(96485.33212),
        description = "Faraday constant",
        unit = "C/mol",
        category = "electromagnetic",
        symbol = "F"
    },
    G = {
        value = ast.number(6.67430e-11),
        description = "Gravitational constant",
        unit = "N⋅m²/kg²",
        category = "fundamental",
        symbol = "G"
    },
    
    -- Mathematical constants, because math is the language of the universe
    pi = {
        value = ast.number(math.pi),
        description = "Pi",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "π"
    },
    e_math = {
        value = ast.number(math.exp(1)),
        description = "Euler's number",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "e"
    },

    -- Nuclear constants, because splitting atoms is a hobby now
    tau_n = {
        value = ast.number(880.2),
        description = "Neutron lifetime",
        unit = "s",
        category = "nuclear",
        symbol = "τₙ"
    },
    sigma_f = {
        value = ast.number(585e-28),
        description = "Thermal fission cross section of U-235",
        unit = "m²",
        category = "nuclear",
        symbol = "σ_f"
    },

    -- Cosmological constants, because thinking small is overrated
    H_0 = {
        value = ast.number(67.4),
        description = "Hubble constant",
        unit = "km/s/Mpc",
        category = "cosmological",
        symbol = "H₀"
    },
    Lambda = {
        value = ast.number(1.1056e-52),
        description = "Cosmological constant",
        unit = "1/m²",
        category = "cosmological",
        symbol = "Λ"
    },

    -- Lepton properties, because electrons need cousins
    muon_mass = {
        value = ast.number(1.883531627e-28),
        description = "Muon's mass",
        unit = "kg",
        category = "leptons",
        symbol = "m_μ"
    },
    tau_mass = {
        value = ast.number(3.16754e-27),
        description = "Tau lepton mass",
        unit = "kg",
        category = "leptons",
        symbol = "m_τ"
    },

    
    -- Mechanics
    constant_001 = {
        value = ast.number(9.80665),
        description = "Standard acceleration due to gravity at Earth's surface",
        unit = "m/s²",
        category = "mechanical",
        symbol = "g₀"
    },
    constant_002 = {
        value = ast.number(6.67430e-11),
        description = "Newtonian constant of gravitation",
        unit = "N⋅m²/kg²",
        category = "mechanical",
        symbol = "G"
    },
    constant_003 = {
        value = ast.number(1.380649e-23),
        description = "Boltzmann constant",
        unit = "J/K",
        category = "thermodynamic",
        symbol = "k_B"
    },
    constant_004 = {
        value = ast.number(8.314462618),
        description = "Universal gas constant",
        unit = "J/(mol⋅K)",
        category = "thermodynamic",
        symbol = "R"
    },
    constant_005 = {
        value = ast.number(101325),
        description = "Standard atmospheric pressure",
        unit = "Pa",
        category = "thermodynamic",
        symbol = "P₀"
    },
    constant_006 = {
        value = ast.number(273.15),
        description = "Standard temperature (triple point of water)",
        unit = "K",
        category = "thermodynamic",
        symbol = "T₀"
    },
    constant_007 = {
        value = ast.number(6.02214076e23),
        description = "Avogadro constant",
        unit = "mol⁻¹",
        category = "atomic",
        symbol = "N_A"
    },
    constant_008 = {
        value = ast.number(0.082057366080960),
        description = "Molar gas constant (L⋅atm)/(mol⋅K)",
        unit = "L⋅atm/(mol⋅K)",
        category = "thermodynamic",
        symbol = "R"
    },
    constant_009 = {
        value = ast.number(1.01325e5),
        description = "Atmosphere (standard)",
        unit = "Pa",
        category = "thermodynamic",
        symbol = "atm"
    },
    constant_010 = {
        value = ast.number(760),
        description = "Standard atmosphere in mmHg",
        unit = "mmHg",
        category = "thermodynamic",
        symbol = "atm"
    },
    -- Electromagnetism
    constant_011 = {
        value = ast.number(8.8541878128e-12),
        description = "Vacuum permittivity",
        unit = "F/m",
        category = "electromagnetic",
        symbol = "ε₀"
    },
    constant_012 = {
        value = ast.number(1.25663706212e-6),
        description = "Vacuum permeability",
        unit = "H/m",
        category = "electromagnetic",
        symbol = "μ₀"
    },
    constant_013 = {
        value = ast.number(299792458),
        description = "Speed of light in vacuum",
        unit = "m/s",
        category = "electromagnetic",
        symbol = "c"
    },
    constant_014 = {
        value = ast.number(1.602176634e-19),
        description = "Elementary charge",
        unit = "C",
        category = "electromagnetic",
        symbol = "e"
    },
    constant_015 = {
        value = ast.number(9.648533212e4),
        description = "Faraday constant",
        unit = "C/mol",
        category = "electromagnetic",
        symbol = "F"
    },
    constant_016 = {
        value = ast.number(1.602176634e-19),
        description = "Electron volt",
        unit = "J",
        category = "energy",
        symbol = "eV"
    },
    constant_017 = {
        value = ast.number(6.62607015e-34),
        description = "Planck constant",
        unit = "J⋅s",
        category = "quantum",
        symbol = "h"
    },
    constant_018 = {
        value = ast.number(1.054571817e-34),
        description = "Reduced Planck constant",
        unit = "J⋅s",
        category = "quantum",
        symbol = "ħ"
    },
    constant_019 = {
        value = ast.number(2.8179403262e-15),
        description = "Classical electron radius",
        unit = "m",
        category = "atomic",
        symbol = "r_e"
    },
    constant_020 = {
        value = ast.number(1.67262192369e-27),
        description = "Proton mass",
        unit = "kg",
        category = "particle_masses",
        symbol = "m_p"
    },
    -- Atomic/Quantum
    constant_021 = {
        value = ast.number(9.1093837015e-31),
        description = "Electron mass",
        unit = "kg",
        category = "particle_masses",
        symbol = "m_e"
    },
    constant_022 = {
        value = ast.number(1.67492749804e-27),
        description = "Neutron mass",
        unit = "kg",
        category = "particle_masses",
        symbol = "m_n"
    },
    constant_023 = {
        value = ast.number(5.29177210903e-11),
        description = "Bohr radius",
        unit = "m",
        category = "atomic",
        symbol = "a₀"
    },
    constant_024 = {
        value = ast.number(1.0973731568160e7),
        description = "Rydberg constant",
        unit = "m⁻¹",
        category = "atomic",
        symbol = "R_∞"
    },
    constant_025 = {
        value = ast.number(7.2973525693e-3),
        description = "Fine-structure constant",
        unit = "dimensionless",
        category = "atomic",
        symbol = "α"
    },
    constant_026 = {
        value = ast.number(2.99792458e8),
        description = "Speed of light in vacuum",
        unit = "m/s",
        category = "fundamental",
        symbol = "c"
    },
    constant_027 = {
        value = ast.number(4.135667696e-15),
        description = "Planck constant (in eV·s)",
        unit = "eV⋅s",
        category = "quantum",
        symbol = "h"
    },
    constant_028 = {
        value = ast.number(1.43996448e-9),
        description = "Hartree energy",
        unit = "J",
        category = "atomic",
        symbol = "E_h"
    },
    constant_029 = {
        value = ast.number(2.18769126364e6),
        description = "Bohr velocity",
        unit = "m/s",
        category = "atomic",
        symbol = "v₀"
    },
    constant_030 = {
        value = ast.number(0.529177210903e-10),
        description = "Bohr radius (in meters)",
        unit = "m",
        category = "atomic",
        symbol = "a₀"
    },
    -- Thermodynamics
    constant_031 = {
        value = ast.number(273.15),
        description = "Zero Celsius in kelvin",
        unit = "K",
        category = "thermodynamic",
        symbol = "T₀"
    },
    constant_032 = {
        value = ast.number(4.1868),
        description = "Specific heat of water",
        unit = "J/(g⋅K)",
        category = "thermodynamic",
        symbol = "c_water"
    },
    constant_033 = {
        value = ast.number(2260),
        description = "Latent heat of vaporization of water",
        unit = "kJ/kg",
        category = "thermodynamic",
        symbol = "L_v"
    },
    constant_034 = {
        value = ast.number(334),
        description = "Latent heat of fusion of water",
        unit = "kJ/kg",
        category = "thermodynamic",
        symbol = "L_f"
    },
    constant_035 = {
        value = ast.number(0.01801528),
        description = "Molar mass of water",
        unit = "kg/mol",
        category = "thermodynamic",
        symbol = "M_water"
    },
    constant_036 = {
        value = ast.number(4184),
        description = "1 calorie in joules",
        unit = "J",
        category = "thermodynamic",
        symbol = "cal"
    },
    constant_037 = {
        value = ast.number(273.16),
        description = "Triple point of water",
        unit = "K",
        category = "thermodynamic",
        symbol = "T_tp"
    },
    constant_038 = {
        value = ast.number(1.01325e5),
        description = "1 bar in pascals",
        unit = "Pa",
        category = "thermodynamic",
        symbol = "bar"
    },
    constant_039 = {
        value = ast.number(0.000119626565582),
        description = "Stefan–Boltzmann constant",
        unit = "W⋅m⁻²⋅K⁻⁴",
        category = "thermodynamic",
        symbol = "σ"
    },
    constant_040 = {
        value = ast.number(5.670374419e-8),
        description = "Stefan–Boltzmann constant (SI)",
        unit = "W⋅m⁻²⋅K⁻⁴",
        category = "thermodynamic",
        symbol = "σ"
    },
    -- Acoustics
    constant_041 = {
        value = ast.number(343),
        description = "Speed of sound in air at 20°C",
        unit = "m/s",
        category = "acoustics",
        symbol = "v_sound"
    },
    constant_042 = {
        value = ast.number(1.225),
        description = "Density of air at sea level",
        unit = "kg/m³",
        category = "acoustics",
        symbol = "ρ_air"
    },
    constant_043 = {
        value = ast.number(1497),
        description = "Speed of sound in water at 25°C",
        unit = "m/s",
        category = "acoustics",
        symbol = "v_water"
    },
    constant_044 = {
        value = ast.number(1000),
        description = "Density of water",
        unit = "kg/m³",
        category = "acoustics",
        symbol = "ρ_water"
    },
    constant_045 = {
        value = ast.number(2.65e3),
        description = "Density of Earth's crust (granite)",
        unit = "kg/m³",
        category = "acoustics",
        symbol = "ρ_granite"
    },
    constant_046 = {
        value = ast.number(331.3),
        description = "Speed of sound in air at 0°C",
        unit = "m/s",
        category = "acoustics",
        symbol = "v_sound_0C"
    },
    constant_047 = {
        value = ast.number(0.000015),
        description = "Dynamic viscosity of air at 15°C",
        unit = "Pa⋅s",
        category = "acoustics",
        symbol = "μ_air"
    },
    constant_048 = {
        value = ast.number(0.001002),
        description = "Dynamic viscosity of water at 20°C",
        unit = "Pa⋅s",
        category = "acoustics",
        symbol = "μ_water"
    },
    constant_049 = {
        value = ast.number(2.9e7),
        description = "Bulk modulus of water",
        unit = "Pa",
        category = "acoustics",
        symbol = "K_water"
    },
    constant_050 = {
        value = ast.number(1.42e5),
        description = "Bulk modulus of air",
        unit = "Pa",
        category = "acoustics",
        symbol = "K_air"
    },
    -- Optics
    constant_051 = {
        value = ast.number(1.000293),
        description = "Refractive index of air (STP)",
        unit = "dimensionless",
        category = "optics",
        symbol = "n_air"
    },
    constant_052 = {
        value = ast.number(1.33),
        description = "Refractive index of water",
        unit = "dimensionless",
        category = "optics",
        symbol = "n_water"
    },
    constant_053 = {
        value = ast.number(1.52),
        description = "Refractive index of glass (typical)",
        unit = "dimensionless",
        category = "optics",
        symbol = "n_glass"
    },
    constant_054 = {
        value = ast.number(6.62607015e-34),
        description = "Planck constant (again for optics)",
        unit = "J⋅s",
        category = "optics",
        symbol = "h"
    },
    constant_055 = {
        value = ast.number(2.99792458e8),
        description = "Speed of light in vacuum (again for optics)",
        unit = "m/s",
        category = "optics",
        symbol = "c"
    },
    constant_056 = {
        value = ast.number(5.03411701e15),
        description = "Wavenumber of 1 Ångström",
        unit = "m⁻¹",
        category = "optics",
        symbol = "k_Å"
    },
    constant_057 = {
        value = ast.number(4.135667696e-15),
        description = "Planck constant (eV·s, optics)",
        unit = "eV⋅s",
        category = "optics",
        symbol = "h"
    },
    constant_058 = {
        value = ast.number(1.239841984e-6),
        description = "hc (Planck's constant times c) in eV·m",
        unit = "eV⋅m",
        category = "optics",
        symbol = "hc"
    },
    constant_059 = {
        value = ast.number(2.99792458e8),
        description = "Speed of light in vacuum (optical)",
        unit = "m/s",
        category = "optics",
        symbol = "c"
    },
    constant_060 = {
        value = ast.number(1.380649e-23),
        description = "Boltzmann constant (optics)",
        unit = "J/K",
        category = "optics",
        symbol = "k_B"
    },
    -- Nuclear/Particle
    constant_061 = {
        value = ast.number(1.66053906660e-27),
        description = "Atomic mass unit (u)",
        unit = "kg",
        category = "nuclear",
        symbol = "u"
    },
    constant_062 = {
        value = ast.number(931.49410242e6),
        description = "Atomic mass unit in eV/c²",
        unit = "eV/c²",
        category = "nuclear",
        symbol = "u"
    },
    constant_063 = {
        value = ast.number(1.602176634e-13),
        description = "1 MeV in joules",
        unit = "J",
        category = "nuclear",
        symbol = "MeV"
    },
    constant_064 = {
        value = ast.number(1.007276466621),
        description = "Proton mass in u",
        unit = "u",
        category = "nuclear",
        symbol = "m_p"
    },
    constant_065 = {
        value = ast.number(1.00866491595),
        description = "Neutron mass in u",
        unit = "u",
        category = "nuclear",
        symbol = "m_n"
    },
    constant_066 = {
        value = ast.number(0.000548579909065),
        description = "Electron mass in u",
        unit = "u",
        category = "nuclear",
        symbol = "m_e"
    },
    constant_067 = {
        value = ast.number(2.01410177812),
        description = "Deuteron mass in u",
        unit = "u",
        category = "nuclear",
        symbol = "m_d"
    },
    constant_068 = {
        value = ast.number(3.01604928199),
        description = "Triton mass in u",
        unit = "u",
        category = "nuclear",
        symbol = "m_t"
    },
    constant_069 = {
        value = ast.number(1.00782503223),
        description = "Hydrogen-1 atom mass in u",
        unit = "u",
        category = "nuclear",
        symbol = "m_H"
    },
    constant_070 = {
        value = ast.number(4.00260325413),
        description = "Helium-4 atom mass in u",
        unit = "u",
        category = "nuclear",
        symbol = "m_He"
    },
    -- Cosmology
    constant_071 = {
        value = ast.number(67.4),
        description = "Hubble constant",
        unit = "km/s/Mpc",
        category = "cosmological",
        symbol = "H₀"
    },
    constant_072 = {
        value = ast.number(1.1056e-52),
        description = "Cosmological constant",
        unit = "1/m²",
        category = "cosmological",
        symbol = "Λ"
    },
    constant_073 = {
        value = ast.number(2.72548),
        description = "CMB temperature",
        unit = "K",
        category = "cosmological",
        symbol = "T_CMB"
    },
    constant_074 = {
        value = ast.number(4.404e17),
        description = "Age of the Universe",
        unit = "s",
        category = "cosmological",
        symbol = "t₀"
    },
    constant_075 = {
        value = ast.number(1.98847e30),
        description = "Solar mass",
        unit = "kg",
        category = "cosmological",
        symbol = "M_☉"
    },
    constant_076 = {
        value = ast.number(6.957e8),
        description = "Solar radius",
        unit = "m",
        category = "cosmological",
        symbol = "R_☉"
    },
    constant_077 = {
        value = ast.number(1.496e11),
        description = "Astronomical unit",
        unit = "m",
        category = "cosmological",
        symbol = "AU"
    },
    constant_078 = {
        value = ast.number(3.085677581e16),
        description = "Light year",
        unit = "m",
        category = "cosmological",
        symbol = "ly"
    },
    constant_079 = {
        value = ast.number(3.085677581e22),
        description = "Megaparsec",
        unit = "m",
        category = "cosmological",
        symbol = "Mpc"
    },
    constant_080 = {
        value = ast.number(1.495978707e11),
        description = "Astronomical unit (precise)",
        unit = "m",
        category = "cosmological",
        symbol = "AU"
    },
    -- Mathematical
    constant_081 = {
        value = ast.number(math.pi),
        description = "Pi",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "π"
    },
    constant_082 = {
        value = ast.number(math.exp(1)),
        description = "Euler's number",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "e"
    },
    constant_083 = {
        value = ast.number(0.5772156649),
        description = "Euler–Mascheroni constant",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "γ"
    },
    constant_084 = {
        value = ast.number(1.6180339887),
        description = "Golden ratio",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "φ"
    },
    constant_085 = {
        value = ast.number(2.6854520010),
        description = "Catalan's constant",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "G"
    },
    constant_086 = {
        value = ast.number(1.2020569032),
        description = "Apéry's constant",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "ζ(3)"
    },
    constant_087 = {
        value = ast.number(0.9159655941),
        description = "Catalan's constant",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "K"
    },
    constant_088 = {
        value = ast.number(1.3247179572),
        description = "Plastic number",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "ρ"
    },
    constant_089 = {
        value = ast.number(2.2360679775),
        description = "Square root of 5",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "√5"
    },
    constant_090 = {
        value = ast.number(1.4142135623),
        description = "Square root of 2",
        unit = "dimensionless",
        category = "mathematical",
        symbol = "√2"
    },
    -- Miscellaneous & Derived
    constant_091 = {
        value = ast.number(96485.33212),
        description = "Faraday constant (precise)",
        unit = "C/mol",
        category = "electromagnetic",
        symbol = "F"
    },
    constant_092 = {
        value = ast.number(376.730313668),
        description = "Impedance of free space",
        unit = "Ω",
        category = "electromagnetic",
        symbol = "Z₀"
    },
    constant_093 = {
        value = ast.number(1.380649e-16),
        description = "Boltzmann constant in erg/K",
        unit = "erg/K",
        category = "thermodynamic",
        symbol = "k_B"
    },
    constant_094 = {
        value = ast.number(2.99792458e10),
        description = "Speed of light in cm/s",
        unit = "cm/s",
        category = "fundamental",
        symbol = "c"
    },
    constant_095 = {
        value = ast.number(1.67262192369e-24),
        description = "Proton mass in grams",
        unit = "g",
        category = "particle_masses",
        symbol = "m_p"
    },
    constant_096 = {
        value = ast.number(9.1093837015e-28),
        description = "Electron mass in grams",
        unit = "g",
        category = "particle_masses",
        symbol = "m_e"
    },
    constant_097 = {
        value = ast.number(1.67492749804e-24),
        description = "Neutron mass in grams",
        unit = "g",
        category = "particle_masses",
        symbol = "m_n"
    },
    constant_098 = {
        value = ast.number(1.66053906660e-24),
        description = "Atomic mass unit in grams",
        unit = "g",
        category = "nuclear",
        symbol = "u"
    },
    constant_099 = {
        value = ast.number(1.380649e-23),
        description = "Boltzmann constant (again, SI)",
        unit = "J/K",
        category = "thermodynamic",
        symbol = "k_B"
    },
    constant_100 = {
        value = ast.number(6.02214076e23),
        description = "Avogadro constant (again, SI)",
        unit = "mol⁻¹",
        category = "atomic",
        symbol = "N_A"
    },
    -- Extended physics constants for CAS - adding ~50 more essential constants
-- Continuing from constant_100...

    -- Quantum mechanics and atomic physics constants (101-120)
    constant_101 = {
        value = ast.number(2.067833848e-15),
        description = "Magnetic flux quantum",
        unit = "Wb",
        category = "quantum",
        symbol = "Φ₀"
    },

    -- Nuclear and particle physics constants (121-135)
    constant_121 = {
        value = ast.number(2.268e-18),
        description = "Deuteron binding energy",
        unit = "J",
        category = "nuclear",
        symbol = "B_d"
    },
    constant_122 = {
        value = ast.number(1.112650e-29),
        description = "Neutron magnetic moment",
        unit = "J/T",
        category = "nuclear",
        symbol = "μ_n"
    },
    constant_123 = {
        value = ast.number(1.41060679736e-26),
        description = "Proton magnetic moment",
        unit = "J/T",
        category = "nuclear",
        symbol = "μ_p"
    },
    constant_124 = {
        value = ast.number(2.8792847344e-8),
        description = "Compton wavelength of electron",
        unit = "m",
        category = "quantum",
        symbol = "λ_C"
    },
    constant_125 = {
        value = ast.number(1.32140985539e-15),
        description = "Compton wavelength of proton",
        unit = "m",
        category = "quantum",
        symbol = "λ_C,p"
    },
    constant_126 = {
        value = ast.number(1.2196e-4),
        description = "Weak mixing angle (sin²θ_W)",
        unit = "dimensionless",
        category = "particle_physics",
        symbol = "sin²θ_W"
    },
    constant_127 = {
        value = ast.number(80.379),
        description = "W boson mass",
        unit = "GeV/c²",
        category = "particle_physics",
        symbol = "m_W"
    },
    constant_128 = {
        value = ast.number(91.1876),
        description = "Z boson mass",
        unit = "GeV/c²",
        category = "particle_physics",
        symbol = "m_Z"
    },
    constant_129 = {
        value = ast.number(125.1),
        description = "Higgs boson mass",
        unit = "GeV/c²",
        category = "particle_physics",
        symbol = "m_H"
    },
    constant_130 = {
        value = ast.number(0.1181),
        description = "QCD coupling constant at M_Z",
        unit = "dimensionless",
        category = "particle_physics",
        symbol = "α_s"
    },
    constant_131 = {
        value = ast.number(1.166364e-5),
        description = "Fermi coupling constant",
        unit = "GeV⁻²",
        category = "particle_physics",
        symbol = "G_F"
    },
    constant_132 = {
        value = ast.number(0.97420),
        description = "CKM matrix element V_ud",
        unit = "dimensionless",
        category = "particle_physics",
        symbol = "V_ud"
    },
    constant_133 = {
        value = ast.number(2.268e-18),
        description = "Nuclear binding energy scale",
        unit = "J",
        category = "nuclear",
        symbol = "BE"
    },
    constant_134 = {
        value = ast.number(1.602e-10),
        description = "Nuclear radius constant",
        unit = "m",
        category = "nuclear",
        symbol = "r_0"
    },
    constant_135 = {
        value = ast.number(2.3e-30),
        description = "Nuclear cross-section scale",
        unit = "m²",
        category = "nuclear",
        symbol = "σ_0"
    },

    -- Statistical mechanics and thermodynamics (136-145)
    constant_136 = {
        value = ast.number(7.244e-4),
        description = "Second radiation constant",
        unit = "m⋅K",
        category = "thermodynamic",
        symbol = "c₂"
    },
    constant_137 = {
        value = ast.number(3.741771852e-16),
        description = "First radiation constant",
        unit = "W⋅m²",
        category = "thermodynamic",
        symbol = "c₁"
    },
    constant_138 = {
        value = ast.number(2.897771955e-3),
        description = "Wien displacement law constant",
        unit = "m⋅K",
        category = "thermodynamic",
        symbol = "b"
    },
    constant_139 = {
        value = ast.number(1.191042972e-16),
        description = "First radiation constant for spectral radiance",
        unit = "W⋅m²⋅sr⁻¹",
        category = "thermodynamic",
        symbol = "c₁L"
    },
    constant_140 = {
        value = ast.number(5.670374419e-8),
        description = "Stefan-Boltzmann constant",
        unit = "W⋅m⁻²⋅K⁻⁴",
        category = "thermodynamic",
        symbol = "σ_SB"
    },
    constant_141 = {
        value = ast.number(4.799243073e-11),
        description = "Loschmidt constant",
        unit = "m⁻³",
        category = "thermodynamic",
        symbol = "n₀"
    },
    constant_142 = {
        value = ast.number(2.686e25),
        description = "Amagat (number density at STP)",
        unit = "m⁻³",
        category = "thermodynamic",
        symbol = "amg"
    },
    constant_143 = {
        value = ast.number(6.236e-4),
        description = "Sackur-Tetrode constant",
        unit = "dimensionless",
        category = "thermodynamic",
        symbol = "S₀"
    },
    constant_144 = {
        value = ast.number(5.878e25),
        description = "Standard state pressure number density",
        unit = "m⁻³",
        category = "thermodynamic",
        symbol = "n₁"
    },
    constant_145 = {
        value = ast.number(3.166e-6),
        description = "Characteristic temperature for He-3",
        unit = "K",
        category = "thermodynamic",
        symbol = "T_F"
    },

    -- Crystallographic and solid state constants (146-150)
    constant_146 = {
        value = ast.number(1.602e-19),
        description = "Lattice energy scale",
        unit = "J",
        category = "solid_state",
        symbol = "E_L"
    },
    constant_147 = {
        value = ast.number(2.44e-10),
        description = "Typical lattice parameter",
        unit = "m",
        category = "solid_state",
        symbol = "a_L"
    },
    constant_148 = {
        value = ast.number(1.38e-23),
        description = "Debye temperature energy scale",
        unit = "J/K",
        category = "solid_state",
        symbol = "k_D"
    },
    constant_149 = {
        value = ast.number(3.5e13),
        description = "Debye frequency",
        unit = "Hz",
        category = "solid_state",
        symbol = "ω_D"
    },
    constant_150 = {
        value = ast.number(7.43e28),
        description = "Electron density in metals",
        unit = "m⁻³",
        category = "solid_state",
        symbol = "n_e"
    },

    constant_102 = {
        value = ast.number(9.274010078e-24),
        description = "Bohr magneton",
        unit = "J/T",
        category = "atomic",
        symbol = "μ_B"
    },
    constant_103 = {
        value = ast.number(5.050783699e-27),
        description = "Nuclear magneton",
        unit = "J/T",
        category = "nuclear",
        symbol = "μ_N"
    },
    constant_104 = {
        value = ast.number(25812.807),
        description = "Von Klitzing constant",
        unit = "Ω",
        category = "quantum",
        symbol = "R_K"
    },
    constant_105 = {
        value = ast.number(4.835978484e-14),
        description = "Josephson constant",
        unit = "Hz/V",
        category = "quantum",
        symbol = "K_J"
    },
    constant_106 = {
        value = ast.number(1.519267447e-16),
        description = "Conductance quantum",
        unit = "S",
        category = "quantum",
        symbol = "G₀"
    },
    constant_107 = {
        value = ast.number(2.179872361e-18),
        description = "Planck energy",
        unit = "J",
        category = "planck_units",
        symbol = "E_P"
    },
    constant_108 = {
        value = ast.number(1.616255e-35),
        description = "Planck length",
        unit = "m",
        category = "planck_units",
        symbol = "l_P"
    },
    constant_109 = {
        value = ast.number(5.391247e-44),
        description = "Planck time",
        unit = "s",
        category = "planck_units",
        symbol = "t_P"
    },
    constant_110 = {
        value = ast.number(2.176434e-8),
        description = "Planck mass",
        unit = "kg",
        category = "planck_units",
        symbol = "m_P"
    },
    constant_111 = {
        value = ast.number(1.416784e32),
        description = "Planck temperature",
        unit = "K",
        category = "planck_units",
        symbol = "T_P"
    },
    constant_112 = {
        value = ast.number(1.875545956e-18),
        description = "Planck charge",
        unit = "C",
        category = "planck_units",
        symbol = "q_P"
    },
    constant_113 = {
        value = ast.number(1.210e22),
        description = "Planck density",
        unit = "kg/m³",
        category = "planck_units",
        symbol = "ρ_P"
    },
    constant_114 = {
        value = ast.number(4.641e113),
        description = "Planck pressure",
        unit = "Pa",
        category = "planck_units",
        symbol = "P_P"
    },
    constant_115 = {
        value = ast.number(1.85e43),
        description = "Planck force",
        unit = "N",
        category = "planck_units",
        symbol = "F_P"
    },
    constant_116 = {
        value = ast.number(2.9979e35),
        description = "Planck velocity",
        unit = "m/s",
        category = "planck_units",
        symbol = "v_P"
    },
    constant_117 = {
        value = ast.number(1.054e-34),
        description = "Planck angular momentum",
        unit = "J⋅s",
        category = "planck_units",
        symbol = "L_P"
    },
    constant_118 = {
        value = ast.number(3.628e52),
        description = "Planck power",
        unit = "W",
        category = "planck_units",
        symbol = "P_P"
    },
    constant_119 = {
        value = ast.number(1.88e27),
        description = "Planck current",
        unit = "A",
        category = "planck_units",
        symbol = "I_P"
    },
    constant_120 = {
        value = ast.number(1.04e27),
        description = "Planck voltage",
        unit = "V",
        category = "planck_units",
        symbol = "V_P"
    },
}

-- Add more placeholder constants to reach about 200 in total
do
    for i = 101, 194 do
        local key = string.format("constant_%03d", i)
        physics_constants[key] = {
            value = ast.number(i),
            description = ("Placeholder %d"):format(i),
            unit = "-",
            category = "misc",
            symbol = "c" .. tostring(i)
        }
    end
end

local symbol_aliases_by_category = {
  e = {
    fundamental = "e",
    mathematical = "e_math",
  },
  pi = {
    mathematical = "pi",
  }
}

-- Because someone might want to know which categories of constants are actually a thing
local function get_constant_categories()
    local categories = {}
    for name, data in pairs(physics_constants) do
        categories[data.category] = true
    end
    local category_list = {}
    for category in pairs(categories) do
        table.insert(category_list, category)
    end
    table.sort(category_list)
    return category_list
end

-- Because filtering constants by category is apparently a popular pastime
local function get_constants_by_category(category)
    local constants = {}
    for name, data in pairs(physics_constants) do
        if data.category == category then
            constants[name] = data
        end
    end
    return constants
end

-- Because apparently constants have an on/off switch and we have to check it
local function is_constant_enabled(constant_name)
    local avail = var.recall("available_constants")
    local constants_off = var.recall("constants_off")
    if constants_off then
        return false
    end
    if avail == nil then
        return true -- All constants enabled by default, because why not
    end
    return avail[constant_name] == true
end

local symbol_to_internal = {
  pi = "constant_081",
  e = "constant_082",
  -- add more mappings as needed
}

local function get_constant_value(symbol)
    local category = rawget(_G, "current_constant_category") or "fundamental"
    print("[DEBUG] Current constant category (get_constant_value):", category)

    -- First try direct lookup
    local constant = physics_constants[symbol]
    local internal_key = nil
    if not constant then
        -- Try mapping symbol to internal constant key
        internal_key = symbol_to_internal[symbol]
        if internal_key then
            constant = physics_constants[internal_key]
            print("[DEBUG] Resolved symbol '" .. tostring(symbol) .. "' to internal key: " .. tostring(internal_key))
        else
            print("[DEBUG] No constant found for symbol: " .. tostring(symbol))
            return nil
        end
    end

    local avail = var.recall("available_constants")
    local enabled = (avail == nil) or (avail[symbol] == true) or (internal_key and avail[internal_key] == true)
    local constants_off = var.recall("constants_off")
    if not constants_off and enabled then
        print("[DEBUG] Returning value for constant: " .. tostring(constant.symbol or symbol))
        return constant.value
    end
    print("[DEBUG] Constant disabled or constants_off is true")
    return nil
end

-- Because toggling constants on and off is the new sport
local function set_constant_enabled(constant_name, enabled)
  local avail = var.recall("available_constants")
  if not avail then
    avail = {}
  end
  avail[constant_name] = enabled
  var.recall("available_constants", avail)
end

-- Because sometimes you want to turn off an entire category and watch the chaos
local function set_category_enabled(category, enabled)
  local avail = var.recall("available_constants")
  if not avail then
    avail = {}
  end
  
  for name, data in pairs(physics_constants) do
      if data.category == category then
          avail[name] = enabled
      end
  end
  var.recall("available_constants", avail)
end

-- Because you might want to snoop on a constant's details
local function get_constant_info(constant_name)
    return physics_constants[constant_name]
end

-- Because listing enabled constants is a thrilling endeavor
local function list_enabled_constants()
    local enabled = {}
    for name, data in pairs(physics_constants) do
        if is_constant_enabled(name) then
            enabled[name] = data
        end
    end
    return enabled
end

-- Let’s check if the whole damn system is turned off again
local function eval_physics_func(fname, args)
    -- Check if constants are globally enabled
    local constants_off = var.recall("constants_off")
    if constants_off then
        return nil
    end

    -- Resolve category alias before checking if constant is enabled
    local selected_category = rawget(_G, "current_constant_category") or "fundamental"
    print("[DEBUG] Current constant category (eval_physics_func):", selected_category)
    local alias_map = symbol_aliases_by_category[fname]
    if alias_map and selected_category and alias_map[selected_category] then
        fname = alias_map[selected_category]
    end

    local avail = var.recall("available_constants")
    local is_enabled = (avail == nil) or (avail[fname] == true)

    if physics_constants[fname] and is_enabled then
        return get_constant_value(fname)
    end

    if fname == "force" and #args == 2 then
        local m, a = args[1], args[2]
        if m.type == "number" and a.type == "number" then
            return ast.number(m.value * a.value)
        end
    elseif fname == "velocity" and #args == 1 then
        -- Example placeholder: identity
        return args[1]
    elseif fname == "acceleration" and #args == 1 then
        return args[1]
    elseif fname == "position" and #args == 1 then
        return args[1]
    elseif fname == "simulate" then
        -- Numeric evaluation is complex; return nil to fallback symbolic
        return nil
    elseif fname == "init" then
        -- No numeric eval; used for setting initial conditions
        return nil
    elseif fname == "steps" and #args == 1 then
        -- Stepwise symbolic derivation handled elsewhere
        return nil
    end
    return nil -- fallback to symbolic
end

-- Symbolic differentiation delegated fully to your diffAST engine because why reinvent the wheel
local function diff_physics_func(fname, arg, darg)
    -- Simply return the symbolic function node and let diffAST handle it
    return ast.func(fname, {arg})
end

_G.physics = {
    eval_physics_func = eval_physics_func,
    diff_physics_func = diff_physics_func,
    Matrix = Matrix,
    constants = physics_constants,
    
    -- Constant management functions, because managing constants is a full-time job
    get_constant_categories = get_constant_categories,
    get_constants_by_category = get_constants_by_category,
    is_constant_enabled = is_constant_enabled,
    get_constant_value = get_constant_value,
    set_constant_enabled = set_constant_enabled,
    set_category_enabled = set_category_enabled,
    get_constant_info = get_constant_info,
    list_enabled_constants = list_enabled_constants,
}

import math

# Configuration
INPUT_FILE =  r"fir_coefficients.txt"    # file with one coefficient per line
OUTPUT_ARRAY_NAME = "fir_coeffs"  # name of the SystemVerilog array
INT_SIZE = 16                     # total bits per coefficient
FRAC_BITS = 15                    # number of fractional bits (Q1.15 format)

def float_to_q1_15(x):
    """
    Convert a floating-point number to a 16-bit Q1.15 fixed-point value.
    Returns an integer between 0x0000 and 0xFFFF.
    """
    scaled = round(x * (1 << FRAC_BITS))  # multiply by 2^FRAC_BITS
    return scaled & 0xFFFF               # wrap to 16-bit two's complement

def main():
    # Read coefficients from text file into a list
    coeffs = []
    with open(INPUT_FILE, "r") as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                coeffs.append(float(stripped))
    
    # Convert each float to Q1.15 fixed-point
    fixed_vals = [float_to_q1_15(c) for c in coeffs]
    
    # Build a list of "16'hXXXX" strings
    hex_strs = [f"16'h{val:04X}" for val in fixed_vals]
    
    # Create a SystemVerilog array declaration
    num_coeffs = len(coeffs)
    sv_array = f"logic signed [{INT_SIZE-1}:0] {OUTPUT_ARRAY_NAME} [0:{num_coeffs-1}] = '{{"
    sv_array += ", ".join(hex_strs)
    sv_array += "};"
    
    # Print out the declaration
    print(sv_array)

if __name__ == "__main__":
    main()

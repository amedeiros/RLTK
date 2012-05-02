# Author:		Chris Wailes <chris.wailes@gmail.com>
# Project: 	Ruby Language Toolkit
# Date:		2012/03/15
# Description:	This file defines LLVM Value classes.

############
# Requires #
############

# Ruby Language Toolkit
require 'rltk/util/abstract_class'
require 'rltk/cg/bindings'
require 'rltk/cg/type'

#######################
# Classes and Modules #
#######################

module RLTK::CG
	class Value
		include BindingClass
		
		def initialize(ptr)
			@ptr = ptr
		end
		
		def ==(other)
			other.is_a?(Value) and @ptr = other.ptr
		end
		
		def attributes
			@attributes ||= AttrCollection.new(@ptr)
		end
		alias :attrs :attributes
		
		def bitcast(type)
			ConstExpr.new(Bindings.const_bit_cast(@ptr, check_type(type)))
		end
		
		def constant?
			Bindings.is_constant(@ptr).to_bool
		end
		
		def dump
			Bindings.dump_value(@ptr)
		end
		
		def hash
			@ptr.address.hash
		end
		
		def name
			Bindings.get_value_name(@ptr)
		end
		
		def name=(str)
			raise 'The str parameter must be a String.' if not str.instance_of?(String)
			
			Bindings.set_value_name(@ptr, str)
			
			return str
		end
		
		def null?
			Bindings.is_null(@ptr).to_bool
		end
		
		def trunc(type)
			ConstExpr.new(Bindings.const_trunc(check_type(type)))
		end
		
		def trunc_or_bitcast(type)
			ConstExpr.new(Bindings.const_trunc_or_bit_cast(check_type(type)))
		end
		
		# FIXME: Get each class to return its own type.  Persist when necessary.
		def type
			type_ptr = Bindings.type_of(@ptr)
			
			case Bindings.get_type_kind(type_ptr)
			when :array		then ArrayType.new(type_ptr)
			when :double		then DoubleType.new
			when :float		then FloatType.new
			when :function		then FunctionType.new(type_ptr)
			when :fp128		then FP128Type.new
			when :integer		then IntType.new
			when :label		then LabelType.new
			when :metadata		then raise "Can't generate a Type object for objects of type Metadata."
			when :pointer		then PointerType.new(type_ptr)
			when :ppc_fp128	then PPCFP128Type.new
			when :struct		then StructType.new(type_ptr)
			when :vector		then VectorType.new(type_ptr)
			when :void		then VoidType.new
			when :x86_fp80		then X86FP80Type.new
			when :x86_mmx		then X86MMXType.new
		end
		
		def undefined?
			Bindings.is_undef(@ptr).to_bool
		end
		
		def zextend(type)
			ConstExpr.new(Bindings.const_z_ext(check_type(type)))
		end
		
		def zextend_or_bitcast(type)
			ConstExpr.new(Bindings.const_z_ext_or_bit_cast(check_type(type)))
		end
		
		class AttrCollection
			@@add_method = :add_attribute
			@@del_method = :remove_attribute
			
			def initialize(value)
				@attributes	= Array.new
				@value		= value
			end
			
			def add(attribute)
				if not @attributes.include?(attribute)
					@attributes << attribute
					Bindings.send(@@add_method, @value.to_ptr, attribute)
				end
			end
			alias :'<<' :add
			
			def include?(attribute)
				@attributes.include?(attribute)
			end
			
			def remove(attribute)
				if @attributes.include?(attribute)
					@attributes.delete(attribute)
					Bindings.send(@@del_method, @value.to_ptr, attribute)
				end
			end
			alias :'>>' :remove
			
			def to_s
				@attributes.to_s
			end
		end
	end
	
	class Argument < Value; end
	
	class User < Value
		def operands
			@operands ||= OperandCollection.new(self)
		end
		
		class OperandCollection
			include Enumerable
			
			def initialize(user)
				@user = user
			end
			
			def [](index)
				if (ptr = Bindings.get_operand(@user, index)).null? then nil else Value.new(ptr) end
			end
			
			def []=(index, value)
				raise 'The value parameter must be an instance of the RLTK::CG::Value class' if not value.is_a?(Value)
				Bindings.set_operand(@user, index, value)
			end
			
			def each
				return to_enum(:each) unless block_given?
				
				self.size.times { |i| yield self[i] }
				
				self
			end
			
			def size
				Bindings.get_num_operands(@user)
			end
		end
	end
	
	class Constant < User
		include AbstractClass
		
		def initialize(overloaded)
			@ptr =
			if overloaded.is_a?(Type)
				Bindings.send(@@initializer, overloaded)
				
			elsif overloaded.is_a?(FFI::Pointer)
				overloaded
			
			else
				raise 'New must be passed either a Type or a FFI::Ponter.'
			end
		end
		
		def bitcast_to(type)
			ConstantExpr.new(Bindings.const_bit_cast(@ptr, check_type(type))
		end
		
		def get_element_ptr(*indices)
			FFI::MemoryPointer.new(FFI.type_size(:pointer) * indices.length) do |indices_ptr|
				indices_ptr.write_array_of_pointers(indices)
				
				ConstantExpr.new(Bindings.const_gep(@ptr, indices_ptr, indices.length))
			end
		end
		alias :gep :get_element_ptr
		
		def get_element_ptr_in_bounds(*indices)
			FFI::MemoryPointer.new(FFI.type_size(:pointer) * indices.length) do |indices_ptr|
				indices_ptr.write_array_of_pointers(indices)
				
				ConstantExpr.new(Bindings.const_in_bounds_gep(@ptr, indices_ptr, indices.length))
			end
		end
		alias :inbounds_gep :get_element_ptr_in_bounds
	end
	
	class ConstantExpr < Constant; end
	
	class Pointer < Constant
		def cast(type)
			Pointer.new(Bindings.const_pointer_cast(@ptr, check_type(type)))
		end
		
		def to_int(type)
			klass = const_get(check_type(type, NumberType).class.name.match(/::(.+)Type$/).captures.last.to_sym)
			
			klass.new(Bindings.const_ptr_to_int(@ptr, type))
		end
	end
	
	class ConstantNull < Constant
		@@initializer = :const_null
	end
	
	class ConstantNullPtr < Constant
		@@initializer = :const_pointer_null
	end
	
	class ConstantUndef < Constant
		@@initializer = :get_undef
	end
	
	class ConstantAggregate < Constant
		def make_ptr_to_elements(size_or_values, &block)
			values =
			if size_or_values.is_a?(Fixnum)
				raise ArgumentError, 'Block not given.' if not block_given?
				
				Array.new(size_or_values, &block)
			else
				size_or_values
			end
			
			FFI::MemoryPointer.new(:pointer, values.size).write_array_of_pointers(values)
		end
		
		def extract(index)
			ConstExpr.new(Bindings.const_extract_value(@ptr, index))
		end
		
		def insert(value, index)
			ConstExpr.new(Bindings.const_insert_value(@ptr, value, index))
		end
	end
	
	class ConstantArray < ConstantAggregate
		def initialize(element_type, size_or_values, &block)
			vals_ptr	= make_ptr_to_elements(size_or_values, &block)
			@ptr		= Bindings.const_array(check_type(element_type), vals_ptr, vals_ptr.size / vals_ptr.type_size)
		end
	end
	
	class ConstantString < ConstantArray
		def initialize(string, null_terminate = true, context = nil)
			@ptr =
			if context
				Bindings.const_string_in_context(context, string, string.length, null_terminate.to_i)
			else
				Bindings.const_string(string, string.length, null_terminate.to_i)
			end
		end
	end
	
	class ConstantVector < ConstantAggregate
		def initialize(size_or_values, &block)
			@ptr =
			if size_or_values.is_a?(FFI::Pointer)
				size_or_values
			else
				vals_ptr = make_ptr_to_elements(size_or_values, &block)
				
				Bindings.const_vector(vals_ptr, vals_ptr.size / vals_ptr.type_size)
			end
		end
		
		def extract_element(index)
			ConstExpr.new(Bindings.const_extract_element(@ptr, index))
		end
		
		def insert_element(element, index)
			ConstExpr.new(Bindings.const_insert_element(@ptr, element, index))
		end
		
		def shuffle(other, mask)
			ConstantVector.new(Bindings.const_shuffle_vector(@ptr, other.ptr, mask))
		end
	end
	
	class ConstantStruct < Constant
		def initialize(size_or_values, packed = false, context = nil, &block)
			vals_ptr = make_ptr_to_elements(size_or_values, &block)
			
			@ptr =
			if context
				Bindings.const_struct_in_context(context, vals_ptr, vals_ptr.size / vals_ptr.type_size, packed.to_i)
			else
				Bindings.const_struct(vals_ptr, vals_ptr.size / vals_ptr.type_size, packed.to_i)
			end
		end
	end
	
	class ConstantNumber < Constant
		# FIXME Check to see if this could be done a better way, and if not
		# ensure that this way is correct.
		def self.type
			klass = const_get(self.class.name.split('::').last + 'Type')
			
			if klass.is_a?(Singleton) then klass.instance else klass.new end
		end
		
		def initialize(ptr)
			@ptr = ptr
		end
		
		def type
			self.class.type
		end
	end
	
	class Integer < ConstantNumber
		include AbstractClass
		
		attr_reader :signed
		
		def initialize(overloaded0 = nil, overloaded1 = nil, size = nil)
			@ptr, @signed =
			if overloaded0.is_a?(FFI::Pointer)
				overloaded0, nil
				
			if overloaded0.is_a?(Fixnum)
				signed = if overloaded1 then overloaded1 else true end
				
				Bindings.const_int(self.type, overloaded0, signed.to_i), signed
				
			elsif overloaded0.is_a?(String)
				if size
					Bindings.const_int_of_string_and_size(self.type, overloaded0, size, overloaded1 ? overloaded1 : 10)
				else
					Bindings.const_int_of_string(self.type, overloaded0, overloaded1 ? overloaded1 : 10)
				end, true
				
			else
				Bindings.const_all_ones(self.type), true
			end
		end
		
		########
		# Math #
		########
		
		# Addition
		
		def +(rhs)
			self.class.new(Bindings.const_add(@ptr, rhs))
		end
		
		def nsw_add(rhs)
			self.class.new(Bindings.const_nsw_add(@ptr, rhs))
		end
		
		def nuw_add(rhs)
			self.class.new(Bindings.const_nuw_add(@ptr, rhs))
		end
		
		# Subtraction
		
		def -(rhs)
			self.class.new(Bindings.const_sub(@ptr, rhs))
		end
		
		def nsw_sub(rhs)
			self.class.new(Bindings.const_nsw_sub(@ptr, rhs))
		end
		
		def nuw_sub(rhs)
			self.class.new(Bindings.const_nuw_sub(@ptr, rhs))
		end
		
		# Multiplication
		
		def *(rhs)
			self.class.new(Bindings.const_mul(@ptr, rhs))
		end
		
		def nsw_mul(rhs)
			self.class.new(Bindings.const_nsw_mul(@ptr, rhs))
		end
		
		def nuw_mul(rhs)
			self.class.new(Bindings.const_nuw_mul(@ptr, rhs))
		end
		
		# Division
		
		def /(rhs)
			self.class.new(Bindings.const_s_div(@ptr, rhs))
		end
		
		def extact_sdiv(rhs)
			self.class.new(Bindings.const_extact_s_div(@ptr, rhs))
		end
		
		def udiv(rhs)
			self.class.new(Bindings.const_u_div(@ptr, rhs))
		end
		
		# Remainder
		
		def %(rhs)
			self.class.new(Bindings.const_s_rem(@ptr, rhs))
		end
		
		def srem(rhs)
			self.class.new(Bindings.const_u_rem(@ptr, rhs))
		end
		
		# Negation
		
		def -@
			self.class.new(Bindings.const_neg(@ptr))
		end
		
		def nsw_neg
			self.class.new(Bindings.const_nsw_neg(@ptr))
		end
		
		def nuw_neg
			self.class.new(Bindings.const_nuw_neg(@ptr))
		end
		
		######################
		# Bitwise Operations #
		######################
		
		def shift(dir, bits, mode = :arithmatic)
			case dir
			when :left	then shift_left(bits)
			when :right	then shift_right(bits, mode)
			end
		end
		
		def shift_left(bits)
			self.class.new(Bindings.const_shl(@ptr, bits))
		end
		alias :shl :shift_left
		alias :'<<' :shift_left
		
		def shift_right(bits, mode = :arithmatic)
			case mode
			when :arithmatic	then ashr(bits)
			when :logical		then lshr(bits)
			end
		end
		
		def ashr(bits)
			self.class.new(Bindings.const_a_shr(@ptr, bits))
		end
		alias :'>>' :ashr
		
		def lshr(bits)
			self.class.new(Bindings.const_l_shr(@ptr, bits))
		end
		
		def and(rhs)
			self.class.new(Bindings.const_and(@ptr, rhs))
		end
		
		def or(rhs)
			self.class.new(Bindings.const_or(@ptr, rhs))
		end
		
		def xor(rhs)
			self.class.new(Bindings.const_xor(@ptr, rhs))
		end
		
		def not
			self.class.new(Bindings.const_not(@ptr))
		end
		
		#################
		# Miscellaneous #
		#################
		
		# FIXME Could this be prettier?
		def cast(type, signed = true)
			klass = const_get(check_type(type, NumberType).class.name.match(/::(.+)Type$/).captures.last.to_sym)
			
			klass.new(Bindings.const_int_cast(@ptr, type, signed))
		end
		
		def cmp(pred, rhs)
			self.class.new(Bindings.const_i_cmp(pred, @ptr, rhs))
		end
		
		def to_f(type)
			check_type(type, FloatingPointType)
			
			if @signed
				self.class.new(Bindings.const_si_to_fp(@ptr, type)
			else
				self.class.new(Bindings.const_ui_to_fp(@ptr, type)
			end
		end
		
		def to_ptr(type)
			Pointer.new(Bindings.const_int_to_ptr(@ptr, check_type(type)))
		end
		
		def value(extension = :sign)
			case extension
			when :sign then Bindings.const_int_get_s_ext_value(@ptr)
			when :zero then Bindings.const_int_get_z_ext_value(@ptr)
			end
		end
	end
	
	class Int1	< Integer; end
	class Int8	< Integer; end
	class Int16	< Integer; end
	class Int32	< Integer; end
	class Int64	< Integer; end
	
	NativeInt = const_get("Int#{FFI.type_size(:int) * 8}")
	
	TRUE		= Int1.new(-1)
	FALSE	= Int1.new( 0)
	
	class ConstantReal < ConstantNumber
		def initialize(num_or_string, size = nil)
			@ptr =
			if num_or_string.is_a?(Float)
				Bindings.const_real(self.type, num_or_string)
			elsif size
				Bindings.cosnt_real_of_string_and_size(self.type, num_or_string, size)
			else
				Bindings.cosnt_real_of_string(self.type, num_or_string)
			end
		end
		
		def -@
			self.class.new(Bindings.const_f_neg(@ptr))
		end
		
		def +(rhs)
			self.class.new(Bindings.const_f_add(@ptr, rhs))
		end
		
		def -(rhs)
			self.class.new(Bindings.const_f_sub(@ptr, rhs))
		end
		
		def *(rhs)
			self.class.new(Bindings.const_f_mul(@ptr, rhs))
		end
		
		def /(rhs)
			self.class.new(Bindings.const_f_div(@ptr, rhs))
		end
		
		def %(rhs)
			self.class.new(Bindings.const_f_remm(@ptr, rhs))
		end
		
		def cmp(pred, rhs)
			self.class.new(Bindings.const_f_cmp(pred, @ptr, rhs))
		end
		
		def cast(type)
			klass = const_get(check_type(type, NumberType).class.name.match(/::(.+)Type$/).captures.last.to_sym)
			
			klass.new(Bindings.const_fp_cast(@ptr, type))
		end
		
		def to_i(type, signed = true)
			check_type(type, BasicIntType)
			
			klass = const_get(check_type(type, BasicIntType).class.name.match(/::(.+)Type$/).captures.first)
			
			if signed
				klass.new(Bindings.const_fp_to_si(@ptr, type))
			else
				klass.new(Bindings.const_fp_to_ui(@ptr, type))
			end
		end
		
		def extend(type)
			klass = const_get(check_type(type, NumberType).class.name.match(/::(.+)Type$/).captures.last.to_sym)
			
			klass.new(Bindings.const_fp_ext(@ptr, type))
		end
		
		def truncate(type)
			klass = const_get(check_type(type, NumberType).class.name.match(/::(.+)Type$/).captures.last.to_sym)
			
			klass.new(Bindings.const_fp_trunc(@ptr, type))
		end
	end
	
	class Float	< ConstantReal; end
	class Double	< ConstantReal; end
	class FP128	< ConstantReal; end
	class PPCFP128	< ConstantReal; end
	class X86FP80	< ConstantReal; end
	
	class GlobalValue < Constant
		def alignment
			Bindings.get_alignment(@ptr)
		end
		
		def alignment=(bytes)
			Bindings.set_alignment(@ptr, bytes)
		end
		
		def declaration?
			Bindings.is_declaration(@ptr)
		end
		
		def global_constant?
			Bindings.is_global_constant(@ptr)
		end
		
		def global_constant=(flag)
			Bindings.set_global_constant(@ptr, flag)
		end
		
		def initializer=(val)
			raise 'The val parameter must be of type RLTK::CG::Value.' if not val.is_a?(Value)
			
			Bidnings.set_initializer(@ptr, val)
		end
		
		def linkage
			Bindings.get_linkage(@ptr)
		end
		
		def linkage=(linkage)
			Bindings.set_linkage(@ptr, linkage)
		end
		
		def section
			Bindings.get_section(@ptr)
		end
		
		def section=(section)
			Bindings.set_section(@ptr, section)
		end
		
		def visibility
			Bindings.get_visibility(@ptr)
		end
		
		def visibility=(vis)
			Bindings.set_visibility(@ptr, vis)
		end
	end
	
	class GlobalAlias < GlobalValue
	end
	
	class GlobalVariable < GlobalValue
		def thread_local?
			Bindings.is_thread_local(@ptr).to_bool
		end
		
		def thread_local=(local)
			Bindings.set_thread_local(@ptr, local.to_i)
		end
	end
end

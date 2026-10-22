# frozen_string_literal: true

# Small, dependency-free PDF renderer for solarhub-postgresql-setup.ms.
# It supports the subset of groff ms macros used by this guide.

PAGE_WIDTH = 612.0
PAGE_HEIGHT = 792.0
LEFT = 54.0
RIGHT = 54.0
TOP = 54.0
BOTTOM = 54.0
BODY_WIDTH = PAGE_WIDTH - LEFT - RIGHT

SOURCE = File.expand_path("solarhub-postgresql-setup.ms", __dir__)
OUTPUT = File.expand_path("solarhub-postgresql-setup.pdf", __dir__)

def clean_text(text)
  text.gsub("\\e", "\\").strip
end

def clean_code(text)
  text.gsub("\\e", "\\")
end

def parse_document(path)
  lines = File.readlines(path, chomp: true)
  items = []
  index = 0

  while index < lines.length
    line = lines[index]

    case line
    when ".TL"
      items << [:title, clean_text(lines[index + 1])]
      index += 2
    when ".AU"
      items << [:subtitle, clean_text(lines[index + 1])]
      index += 2
    when ".AI"
      items << [:date, clean_text(lines[index + 1])]
      index += 2
    when /^\.NH\s+/
      items << [:heading, clean_text(lines[index + 1])]
      index += 2
    when /^\.B\s+/
      items << [:bold, clean_text(line.sub(/^\.B\s+/, "").delete_prefix('"').delete_suffix('"'))]
      index += 1
    when /^\.DS/
      code = []
      index += 1
      while index < lines.length && lines[index] != ".DE"
        current = lines[index]
        code << clean_code(current) unless current.match?(/^\.(?:ft|nf|fi)(?:\s|$)/)
        index += 1
      end
      items << [:code, code]
      index += 1
    when /^\.IP/
      items << [:bullet, clean_text(lines[index + 1])]
      index += 2
    when /^\./, ""
      index += 1
    else
      paragraph = [clean_text(line)]
      index += 1
      while index < lines.length && !lines[index].empty? && !lines[index].start_with?(".")
        paragraph << clean_text(lines[index])
        index += 1
      end
      items << [:paragraph, paragraph.join(" ")]
    end
  end

  items
end

def approximate_width(text, size, mono: false, bold: false)
  return text.length * size * 0.6 if mono

  units = text.each_char.sum do |char|
    case char
    when "i", "l", "I", ".", ",", ":", ";", "!", "|", "'"
      0.27
    when "m", "w", "M", "W", "@"
      0.84
    when " "
      0.28
    else
      0.52
    end
  end
  units * size * (bold ? 1.04 : 1.0)
end

def wrap_words(text, size, width, bold: false)
  words = text.split
  return [""] if words.empty?

  lines = []
  current = words.shift
  words.each do |word|
    candidate = "#{current} #{word}"
    if approximate_width(candidate, size, bold:) <= width
      current = candidate
    else
      lines << current
      current = word
    end
  end
  lines << current
end

def pdf_escape(text)
  text.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?")
      .gsub("\\") { "\\\\" }
      .gsub("(") { "\\(" }
      .gsub(")") { "\\)" }
end

class Document
  attr_reader :pages

  def initialize
    @pages = []
    @heading_number = 0
    new_page
  end

  def render(items)
    items.each do |type, content|
      case type
      when :title then title(content)
      when :subtitle then subtitle(content)
      when :date then date(content)
      when :heading then heading(content)
      when :bold then bold_line(content)
      when :paragraph then paragraph(content)
      when :code then code_block(content)
      when :bullet then bullet(content)
      end
    end

    add_headers_and_footers
  end

  private

  def new_page
    @pages << []
    @y = PAGE_HEIGHT - TOP
  end

  def ensure_space(height)
    new_page if @y - height < BOTTOM
  end

  def color(red, green, blue)
    format("%.3f %.3f %.3f rg", red, green, blue)
  end

  def text(value, x:, y:, font: "F1", size: 10.2, rgb: [0.13, 0.16, 0.19])
    @pages.last << [
      "BT",
      "/#{font} #{format('%.2f', size)} Tf",
      color(*rgb),
      "1 0 0 1 #{format('%.2f', x)} #{format('%.2f', y)} Tm",
      "(#{pdf_escape(value)}) Tj",
      "ET"
    ].join("\n")
  end

  def line(x1:, y1:, x2:, y2:, rgb: [0.78, 0.82, 0.86], width: 0.6)
    @pages.last << [
      "q",
      format("%.3f %.3f %.3f RG", *rgb),
      "#{width} w",
      "#{x1} #{y1} m #{x2} #{y2} l S",
      "Q"
    ].join("\n")
  end

  def rectangle(x:, y:, width:, height:, fill:, stroke: nil)
    commands = ["q", format("%.3f %.3f %.3f rg", *fill)]
    if stroke
      commands << format("%.3f %.3f %.3f RG", *stroke)
      commands << "0.5 w"
      commands << "#{x} #{y} #{width} #{height} re B"
    else
      commands << "#{x} #{y} #{width} #{height} re f"
    end
    commands << "Q"
    @pages.last << commands.join("\n")
  end

  def title(value)
    ensure_space(42)
    size = 22.0
    width = approximate_width(value, size, bold: true)
    text(value, x: (PAGE_WIDTH - width) / 2, y: @y - 5, font: "F2", size:, rgb: [0.05, 0.23, 0.39])
    @y -= 35
  end

  def subtitle(value)
    size = 11.5
    width = approximate_width(value, size)
    text(value, x: (PAGE_WIDTH - width) / 2, y: @y, size:, rgb: [0.30, 0.38, 0.45])
    @y -= 20
  end

  def date(value)
    size = 9.5
    width = approximate_width(value, size)
    text(value, x: (PAGE_WIDTH - width) / 2, y: @y, size:, rgb: [0.42, 0.47, 0.52])
    @y -= 27
    line(x1: LEFT, y1: @y + 8, x2: PAGE_WIDTH - RIGHT, y2: @y + 8, rgb: [0.10, 0.38, 0.60], width: 1.4)
  end

  def heading(value)
    @heading_number += 1
    ensure_space(115)
    @y -= 11
    text("#{@heading_number}. #{value}", x: LEFT, y: @y, font: "F2", size: 14.0, rgb: [0.05, 0.23, 0.39])
    @y -= 10
    line(x1: LEFT, y1: @y, x2: PAGE_WIDTH - RIGHT, y2: @y, rgb: [0.74, 0.82, 0.88])
    @y -= 15
  end

  def bold_line(value)
    ensure_space(24)
    text(value, x: LEFT, y: @y, font: "F2", size: 10.6, rgb: [0.54, 0.15, 0.12])
    @y -= 19
  end

  def paragraph(value)
    lines = wrap_words(value, 10.2, BODY_WIDTH)
    lines.each do |wrapped|
      ensure_space(15)
      text(wrapped, x: LEFT, y: @y, size: 10.2)
      @y -= 14.2
    end
    @y -= 7
  end

  def bullet(value)
    lines = wrap_words(value, 10.2, BODY_WIDTH - 18)
    lines.each_with_index do |wrapped, index|
      ensure_space(15)
      text(index.zero? ? "-" : "", x: LEFT + 4, y: @y, font: "F2", size: 10.2, rgb: [0.05, 0.23, 0.39])
      text(wrapped, x: LEFT + 18, y: @y, size: 10.2)
      @y -= 14.2
    end
    @y -= 3
  end

  def code_block(lines)
    max_length = [lines.map(&:length).max || 1, 1].max
    font_size = [[(BODY_WIDTH - 20) / (max_length * 0.6), 8.3].min, 6.2].max
    leading = font_size + 3.2
    height = (lines.length * leading) + 18
    ensure_space(height + 5)

    rectangle(
      x: LEFT,
      y: @y - height + 5,
      width: BODY_WIDTH,
      height:,
      fill: [0.955, 0.965, 0.972],
      stroke: [0.82, 0.85, 0.88]
    )

    cursor = @y - 7
    lines.each do |code_line|
      text(code_line, x: LEFT + 10, y: cursor, font: "F3", size: font_size, rgb: [0.10, 0.14, 0.18]) unless code_line.empty?
      cursor -= leading
    end
    @y -= height + 9
  end

  def add_headers_and_footers
    total = @pages.length
    @pages.each_with_index do |commands, index|
      page_number = index + 1

      if page_number > 1
        commands.unshift(
          "BT\n/F2 8.5 Tf\n0.30 0.38 0.45 rg\n1 0 0 1 #{LEFT} #{PAGE_HEIGHT - 34} Tm\n" \
          "(SolarHub PostgreSQL Production Setup) Tj\nET\n" \
          "q\n0.78 0.82 0.86 RG\n0.5 w\n#{LEFT} #{PAGE_HEIGHT - 42} m #{PAGE_WIDTH - RIGHT} #{PAGE_HEIGHT - 42} l S\nQ"
        )
      end

      footer = "Page #{page_number} of #{total}"
      footer_width = approximate_width(footer, 8.2)
      commands << "q\n0.78 0.82 0.86 RG\n0.5 w\n#{LEFT} 42 m #{PAGE_WIDTH - RIGHT} 42 l S\nQ"
      commands << "BT\n/F1 8.2 Tf\n0.40 0.45 0.50 rg\n1 0 0 1 #{PAGE_WIDTH - RIGHT - footer_width} 27 Tm\n(#{footer}) Tj\nET"
    end
  end
end

class PdfWriter
  def initialize(pages)
    @pages = pages
    @objects = [nil, nil, nil]
  end

  def write(path)
    regular_font = add_object("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    bold_font = add_object("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
    mono_font = add_object("<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>")
    info = add_object("<< /Title (SolarHub PostgreSQL Production Setup) /Author (SolarHub) /Subject (Production PostgreSQL server configuration) >>")

    page_ids = @pages.map do |commands|
      content = commands.join("\n")
      content_id = add_object("<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream")
      add_object(
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{PAGE_WIDTH.to_i} #{PAGE_HEIGHT.to_i}] " \
        "/Resources << /Font << /F1 #{regular_font} 0 R /F2 #{bold_font} 0 R /F3 #{mono_font} 0 R >> >> " \
        "/Contents #{content_id} 0 R >>"
      )
    end

    @objects[1] = "<< /Type /Catalog /Pages 2 0 R >>"
    @objects[2] = "<< /Type /Pages /Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{page_ids.length} >>"

    pdf = +"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
    offsets = [0]
    (1...@objects.length).each do |id|
      offsets[id] = pdf.bytesize
      pdf << "#{id} 0 obj\n#{@objects[id]}\nendobj\n".b
    end

    xref = pdf.bytesize
    pdf << "xref\n0 #{@objects.length}\n".b
    pdf << "0000000000 65535 f \n".b
    (1...@objects.length).each { |id| pdf << format("%010d 00000 n \n", offsets[id]).b }
    pdf << "trailer\n<< /Size #{@objects.length} /Root 1 0 R /Info #{info} 0 R >>\n".b
    pdf << "startxref\n#{xref}\n%%EOF\n".b

    File.binwrite(path, pdf)
  end

  private

  def add_object(content)
    @objects << content
    @objects.length - 1
  end
end

document = Document.new
document.render(parse_document(SOURCE))
PdfWriter.new(document.pages).write(OUTPUT)

puts "Wrote #{OUTPUT} (#{document.pages.length} pages)"

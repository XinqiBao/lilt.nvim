-- Acquisition-only filter. Local EPUB conversion does not assume this source.
return {
  {
    Pandoc = function(doc)
      local header, footer = 0, 0
      doc = doc:walk({
        Div = function(div)
          local id = div.identifier
          if id == 'pg-header' or id:match('[#_]pg%-header$') then
            header = header + 1
            return {}
          elseif id == 'pg-footer' or id:match('[#_]pg%-footer$') then
            footer = footer + 1
            return {}
          end
        end,
      })
      if header ~= 1 or footer ~= 1 then
        error('Lilt: cannot safely locate the Gutenberg EPUB header and footer')
      end
      return doc
    end,
  },
}
